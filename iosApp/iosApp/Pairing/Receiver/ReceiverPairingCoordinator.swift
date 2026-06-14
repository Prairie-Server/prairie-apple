#if os(tvOS)
import Foundation
import OSLog

/// Drives the TV side of a pairing session over an accepted `PairingSession`.
/// Persist-on-success: a pushed server URL is written to ServerRegistry /
/// TokenStore ONLY after its poll returns tokens (design spec §5/§6).
@MainActor
@Observable
final class ReceiverPairingCoordinator {
    enum State: Equatable {
        case idle
        /// Showing the match code for the named server while the phone approves.
        case awaitingApproval(serverName: String, matchCode: String)
        case signedIn(serverCount: Int)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let api: PairingDeviceAPI
    private let onAuthenticated: () -> Void
    private var signedInCount = 0
    /// The in-flight start+poll for the current server. Run as a separate
    /// cancellable task so the stream reader below is NEVER blocked by polling.
    private var pollTask: Task<Void, Never>?
    /// True while `pollTask` is active. The protocol is one-server-at-a-time;
    /// an overlapping PushServer is ignored.
    private var isPolling = false
    private static let logger = Logger(subsystem: "com.continuum.app", category: "pairing.receiver")

    /// - Parameter onAuthenticated: called on the main actor after at least
    ///   one server is signed in, to advance the router to profile selection.
    init(api: PairingDeviceAPI = PairingDeviceAPI(), onAuthenticated: @escaping () -> Void) {
        self.api = api
        self.onAuthenticated = onAuthenticated
    }

    /// Consume the session stream. The stream is ALWAYS being read here; each
    /// server's start+poll runs as a cancellable child task so a Cancel message
    /// or a dropped connection aborts the attempt immediately rather than after
    /// the poll loop finishes (design spec §7).
    func run(session: PairingSession, stream: AsyncThrowingStream<PairingMessage, Error>) async {
        let device = AppleDeviceIdentity.current
        do {
            try await session.send(.hello(
                tvName: device.name,
                tvDeviceId: device.id,
                state: .setup,
                supportedVersions: [PairingProtocol.version]
            ))
            for try await message in stream {
                switch message {
                case let .pushServer(serverURL, serverName):
                    guard !isPolling else { break } // one at a time; ignore overlap
                    isPolling = true
                    pollTask = Task { [weak self] in
                        await self?.handlePushServer(serverURL: serverURL, serverName: serverName, session: session)
                        self?.isPolling = false
                    }
                case .done:
                    await pollTask?.value // let the last server finish persisting
                    if signedInCount > 0 { onAuthenticated() }
                    await teardown(session: session, resetState: false)
                    return
                case let .cancel(reason):
                    Self.logger.notice("peer cancelled: \(reason, privacy: .public)")
                    await teardown(session: session, resetState: true)
                    return
                default:
                    break // Receiver only consumes phone→TV message kinds.
                }
            }
            // Stream ended without a Done (peer closed the connection).
            await teardown(session: session, resetState: true)
        } catch {
            // Stream threw: the connection dropped mid-session.
            Self.logger.error("session error: \(String(describing: error), privacy: .public)")
            await teardown(session: session, resetState: true)
        }
    }

    /// Cancel any in-flight poll, close the session, and (optionally) return the
    /// UI to idle so the advertiser can accept a fresh connection.
    private func teardown(session: PairingSession, resetState: Bool) async {
        pollTask?.cancel()
        await session.close()
        if resetState { state = .idle }
    }

    private func handlePushServer(serverURL: String, serverName: String?, session: PairingSession) async {
        let normalized = ServerRegistry.normalize(url: serverURL)
        let device = AppleDeviceIdentity.current
        do {
            // 1. Start device auth against the PENDING candidate (not persisted).
            let started = try await api.start(serverURL: normalized, deviceName: device.name, devicePlatform: device.platform)
            state = .awaitingApproval(serverName: serverName ?? normalized, matchCode: started.matchCode)
            try await session.send(.deviceStarted(serverURL: normalized, userCode: started.userCode, matchCode: started.matchCode))

            // 2. Poll until approved or the device code expires.
            let deadline = Date().addingTimeInterval(TimeInterval(started.expiresIn))
            while Date() < deadline {
                try Task.checkCancellation() // abort promptly on peer cancel / drop
                let poll = try await api.poll(serverURL: normalized, deviceCode: started.deviceCode)
                switch poll.status {
                case "approved":
                    guard let access = poll.accessToken, let refresh = poll.refreshToken else {
                        throw PairingDeviceAPI.APIError.decode
                    }
                    await persistOnSuccess(url: normalized, fetchedName: serverName, access: access, refresh: refresh)
                    signedInCount += 1
                    state = .signedIn(serverCount: signedInCount)
                    try await session.send(.serverResult(serverURL: normalized, status: .signedIn, error: nil))
                    return
                case "denied", "expired", "consumed":
                    throw PairingDeviceAPI.APIError.http(409)
                default: // "pending"
                    try await Task.sleep(for: .seconds(max(1, poll.pollAfter ?? started.interval)))
                }
            }
            throw PairingDeviceAPI.APIError.http(408) // local timeout
        } catch {
            // Persist-on-success: nothing was written, so nothing to roll back.
            if Task.isCancelled {
                // Peer cancelled or the connection dropped (teardown already reset
                // the UI). The peer is gone, so send nothing.
                Self.logger.notice("attempt for \(normalized, privacy: .public) cancelled")
                return
            }
            Self.logger.error("server \(normalized, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            state = .failed(serverName ?? normalized)
            try? await session.send(.serverResult(serverURL: normalized, status: .failed, error: "auth_failed"))
        }
    }

    /// Commit the now-trusted server + tokens. Runs only after a successful poll.
    private func persistOnSuccess(url: String, fetchedName: String?, access: String, refresh: String) async {
        let id = ServerRegistry.serverId(for: url)
        let entry = ServerEntry(id: id, url: url, fetchedName: fetchedName, userOverrideName: nil, profileId: nil, lastUsedAt: Date())
        ServerRegistry.shared.addOrUpdate(entry)
        await TokenStore.shared.setServerUrl(url)
        await TokenStore.shared.switchActiveServer(serverId: id)
        await TokenStore.shared.saveTokens(accessToken: access, refreshToken: refresh)
        await ServerRegistry.shared.switchTo(serverId: id)
    }
}
#endif
