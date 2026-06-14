#if os(tvOS)
import Foundation
import OSLog

/// Drives the TV side of a pairing session over an accepted `PairingSession`.
/// Persist-on-success: a pushed server URL is written to ServerRegistry /
/// TokenStore ONLY after its poll returns tokens (design spec §5/§6).
///
/// State drives the in-place pairing UI inside `TVServerSetupView`:
/// `idle` (advertising) → `linked` (phone connected, picking servers) →
/// `awaitingApproval` (match code shown) → `signedIn` (per server) →
/// `completed` (all done; the view dwells then advances). Any drop, decline,
/// timeout, or cancel returns to `idle` so a fresh attempt just works.
@MainActor
@Observable
final class ReceiverPairingCoordinator {
    enum State: Equatable {
        case idle
        /// A phone has connected and is choosing servers on its end.
        case linked
        /// Showing the match code for the named server while the phone approves.
        case awaitingApproval(serverName: String, matchCode: String)
        /// A single server finished signing in (interim, during multi-server).
        case signedIn(serverCount: Int)
        /// The phone sent `Done`; every signed-in server, named for the summary.
        case completed(serverNames: [String])
        case failed(String)
    }

    private(set) var state: State = .idle

    private let api: PairingDeviceAPI
    private var signedInCount = 0
    private var signedInNames: [String] = []
    /// The session currently being driven, so `cancel()` can close it from the UI.
    private var activeSession: PairingSession?
    /// The in-flight start+poll for the current server. Run as a separate
    /// cancellable task so the stream reader below is NEVER blocked by polling.
    private var pollTask: Task<Void, Never>?
    /// True while `pollTask` is active. The protocol is one-server-at-a-time;
    /// an overlapping PushServer is ignored.
    private var isPolling = false
    private static let logger = Logger(subsystem: "com.continuum.app", category: "pairing.receiver")

    init(api: PairingDeviceAPI = PairingDeviceAPI()) {
        self.api = api
    }

    /// Consume the session stream. The stream is ALWAYS being read here; each
    /// server's start+poll runs as a cancellable child task so a Cancel message
    /// or a dropped connection aborts the attempt immediately rather than after
    /// the poll loop finishes (design spec §7).
    func run(session: PairingSession, stream: AsyncThrowingStream<PairingMessage, Error>) async {
        signedInCount = 0
        signedInNames = []
        activeSession = session
        let device = AppleDeviceIdentity.current
        do {
            try await session.send(.hello(
                tvName: device.name,
                tvDeviceId: device.id,
                state: .setup,
                supportedVersions: [PairingProtocol.version]
            ))
            // A phone is on the line; it now picks servers on its end.
            state = .linked
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
                    if isPolling { pollTask?.cancel() } // an in-flight server has no committed result
                    await pollTask?.value
                    if signedInCount > 0 { state = .completed(serverNames: signedInNames) }
                    // With zero sign-ins there is no terminal state to dwell on, so
                    // return to idle (like cancel/drop) instead of stranding the panel.
                    await teardown(session: session, resetState: signedInCount == 0)
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

    /// Abort the active session from the UI (Cancel button / leaving the screen).
    /// Closing the session ends the stream, which unwinds `run` back to `idle`.
    func cancel() async {
        pollTask?.cancel()
        isPolling = false
        state = .idle
        await activeSession?.close()
        activeSession = nil
    }

    /// Cancel any in-flight poll, close the session, and (optionally) return the
    /// UI to idle so the advertiser can accept a fresh connection.
    private func teardown(session: PairingSession, resetState: Bool) async {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        await session.close()
        activeSession = nil
        if resetState { state = .idle }
    }

    private func handlePushServer(serverURL: String, serverName: String?, session: PairingSession) async {
        let normalized = ServerRegistry.normalize(url: serverURL)
        let displayName = serverName ?? normalized
        let device = AppleDeviceIdentity.current
        do {
            // 1. Start device auth against the PENDING candidate (not persisted).
            let started = try await api.start(serverURL: normalized, deviceName: device.name, devicePlatform: device.platform)
            state = .awaitingApproval(serverName: displayName, matchCode: started.matchCode)
            try await session.send(.deviceStarted(serverURL: normalized, userCode: started.userCode, matchCode: started.matchCode))

            // 2. Poll until approved or the device code expires.
            let deadline = Date().addingTimeInterval(TimeInterval(started.expiresIn))
            while Date() < deadline {
                try Task.checkCancellation() // abort promptly on peer cancel / drop
                let poll = try await api.poll(serverURL: normalized, deviceCode: started.deviceCode)
                try Task.checkCancellation() // a cancel that raced the network must win — persist nothing
                switch poll.status {
                case "approved":
                    guard let access = poll.accessToken, let refresh = poll.refreshToken else {
                        throw PairingDeviceAPI.APIError.decode
                    }
                    await persistOnSuccess(url: normalized, fetchedName: serverName, access: access, refresh: refresh)
                    signedInCount += 1
                    signedInNames.append(displayName)
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
            state = .failed(displayName)
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
