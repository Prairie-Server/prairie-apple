#if os(iOS)
import Foundation
import OSLog

/// Drives the phone side: connect to a discovered TV, let the user pick which
/// servers to push, confirm the (server-authoritative) match code once, then
/// approve each chosen server. Confirm-once multi-server is an accepted v1
/// risk — see the design spec §6 "Accepted risk".
@MainActor
@Observable
final class CompanionPairingCoordinator {
    enum State: Equatable {
        case connecting
        /// Connected; offer the phone's servers (those with a stored token).
        case pickServers(tvName: String, servers: [ServerEntry])
        /// Awaiting the user's match-code confirmation for the first server.
        case confirmMatch(tvName: String, serverName: String, matchCode: String)
        /// Pushing/approving the remaining servers after confirmation.
        case working(progress: String)
        case finished(signedIn: [String], failed: [String])
        case error(String)
    }

    private(set) var state: State = .connecting

    private let api: PairingDeviceAPI
    private let session: PairingSession
    private let stream: AsyncThrowingStream<PairingMessage, Error>
    private var iterator: AsyncThrowingStream<PairingMessage, Error>.AsyncIterator

    private var tvName = "Apple TV"
    private var queue: [ServerEntry] = []
    private var confirmed = false
    private var pendingUserCode: String?
    private var signedIn: [String] = []
    private var failed: [String] = []
    private static let logger = Logger(subsystem: "com.continuum.app", category: "pairing.companion")

    init(api: PairingDeviceAPI = PairingDeviceAPI(), session: PairingSession, stream: AsyncThrowingStream<PairingMessage, Error>) {
        self.api = api
        self.session = session
        self.stream = stream
        self.iterator = stream.makeAsyncIterator()
    }

    /// Read the TV's `Hello` and present the server picker.
    func begin() async {
        do {
            guard case let .hello(name, _, _, supported)? = try await nextMessage() else {
                state = .error("No response from the Apple TV."); return
            }
            guard supported.contains(PairingProtocol.version) else {
                state = .error("Update Silo on one of your devices to continue."); return
            }
            tvName = name
            let servers = await serversWithTokens()
            guard !servers.isEmpty else {
                state = .error("Sign in to a server on this iPhone first."); return
            }
            state = .pickServers(tvName: name, servers: servers)
        } catch {
            state = .error("Connection lost.")
        }
    }

    /// User tapped a set of servers to push (order = approval order).
    func pushSelected(_ servers: [ServerEntry]) async {
        queue = servers
        await pushNext()
    }

    /// User confirmed the displayed match code matches the TV.
    func confirmMatch() async {
        confirmed = true
        if case .confirmMatch = state, let current = queue.first {
            await approveAndAdvance(current)
        }
    }

    /// User said the codes don't match — abort.
    func declineMatch() async {
        try? await session.send(.cancel(reason: "match_declined"))
        await session.close()
        state = .error("Codes didn’t match — setup cancelled.")
    }

    func cancel() async {
        try? await session.send(.cancel(reason: "user_cancelled"))
        await session.close()
    }

    // MARK: - Internals

    private func pushNext() async {
        guard let server = queue.first else { await finish(); return }
        state = .working(progress: "Setting up \(server.displayName)…")
        do {
            try await session.send(.pushServer(serverURL: server.url, serverName: server.displayName))
            guard case let .deviceStarted(_, userCode, _)? = try await nextRelevant() else {
                fail(server); await pushNext(); return
            }
            // Display the SERVER's authoritative match code, not the channel's.
            let token = await TokenStore.shared.getAccessToken(for: server.id) ?? ""
            let lookup = try await api.lookup(serverURL: server.url, bearer: token, userCode: userCode)
            let serverMatch = lookup.matchCode ?? ""
            pendingUserCode = userCode
            if confirmed {
                await approveAndAdvance(server)
            } else {
                state = .confirmMatch(tvName: tvName, serverName: server.displayName, matchCode: serverMatch)
            }
        } catch {
            fail(server); await pushNext()
        }
    }

    private func approveAndAdvance(_ server: ServerEntry) async {
        state = .working(progress: "Approving \(server.displayName)…")
        do {
            let token = await TokenStore.shared.getAccessToken(for: server.id) ?? ""
            try await api.approve(serverURL: server.url, bearer: token, userCode: pendingUserCode ?? "")
            // Wait for the TV to report it minted tokens.
            if case let .serverResult(_, status, _)? = try await nextRelevant(), status == .signedIn {
                signedIn.append(server.displayName)
            } else {
                failed.append(server.displayName)
            }
        } catch {
            failed.append(server.displayName)
        }
        queue.removeFirst()
        await pushNext()
    }

    private func finish() async {
        try? await session.send(.done)
        await session.close()
        state = .finished(signedIn: signedIn, failed: failed)
    }

    private func fail(_ server: ServerEntry) { failed.append(server.displayName) }

    /// Pull the next deviceStarted/serverResult, ignoring anything else.
    private func nextRelevant() async throws -> PairingMessage? {
        while let message = try await nextMessage() {
            switch message {
            case .deviceStarted, .serverResult: return message
            case .cancel: return nil
            default: continue
            }
        }
        return nil
    }

    /// The phone's servers that currently have a stored access token.
    private func serversWithTokens() async -> [ServerEntry] {
        var result: [ServerEntry] = []
        for entry in ServerRegistry.shared.sortedEntries {
            if await TokenStore.shared.getAccessToken(for: entry.id) != nil { result.append(entry) }
        }
        return result
    }

    /// Advance the stream by one message. `AsyncIterator.next()` is a
    /// `mutating async` method and can't be invoked directly on an
    /// actor-isolated stored property (exclusivity can't be proven across the
    /// suspension). The coordinator drives the stream strictly sequentially on
    /// the main actor, so taking the iterator into a local, awaiting, and
    /// writing it back is safe and single-reader.
    private func nextMessage() async throws -> PairingMessage? {
        var local = iterator
        defer { iterator = local }
        return try await local.next()
    }
}
#endif
