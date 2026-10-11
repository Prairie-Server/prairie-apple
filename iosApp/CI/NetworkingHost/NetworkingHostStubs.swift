import Foundation

extension Notification.Name {
    static let prairieSessionExpired = Notification.Name("prairieSessionExpired")
    static let temporaryRemoteAuthExpired = Notification.Name("temporaryRemoteAuthExpired")
    static let prairieProfileVerificationRequired = Notification.Name("prairieProfileVerificationRequired")
}

/// Minimal stand-ins for app types that gated Networking code references but
/// that would otherwise pull PrairieAPI / Diagnostics / player UI into the
/// FFmpeg-free CI host. Full Prairie.app keeps the real implementations.

final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    enum SignOutAuthorization: Equatable, Sendable {
        case allowed(account: RefreshAccountIdentity?)
        case refused
    }

    var isLoggedIn: Bool = false
    var profileId: String? { nil }

    func clearCachesForServerChange() async {}

    func getProfiles() async throws -> [UserProfile] { [] }

    func resolveActiveProfileForSession(
        holding transitionLease: HTTPIdentityTransitionLease
    ) async -> Bool { false }

    static func signOutAuthorization(
        activeServerId: String?,
        capturedAuth: CapturedOrdinaryRequestAuth?
    ) -> SignOutAuthorization {
        if capturedAuth?.credentialOwner == .temporary {
            return .refused
        }
        guard let activeServerId, !activeServerId.isEmpty else {
            return .allowed(account: capturedAuth?.account)
        }
        guard let capturedAuth else {
            return .allowed(account: nil)
        }
        guard capturedAuth.credentialOwner == .persistentServer(
            serverId: activeServerId
        ), capturedAuth.account.serverId == activeServerId else {
            return .refused
        }
        return .allowed(account: capturedAuth.account)
    }
}

actor DiagnosticsCoordinator {
    static let shared = DiagnosticsCoordinator()

    nonisolated static func activeProfileWillChange() {}
    nonisolated static func activeProfileDidChange() {}

    @discardableResult
    func purgeDiagnosticsForCurrentBinding() async -> Bool { false }

    func purgeDiagnosticsForServerRegistryID(_ serverId: String) async {}
}

@MainActor
final class AICapabilities {
    static let shared = AICapabilities()
    func reset() {}
}

/// PrairieAPI-backed probe; real type is excluded from the FFmpeg-free host
/// the same way ``AICapabilities`` is. ServerRegistry / PrairieAPI only need
/// reset/refresh/requestQuery.
final class ImageSizeCapability: @unchecked Sendable {
    static let shared = ImageSizeCapability()
    var requestQuery: [String: String] { [:] }
    func reset() {}
    func refresh(retryFailed: Bool = true) async {}
    func requestQueryForImageRequest() async -> [String: String] { [:] }
}

/// The API v2 sync removed SubtitleProvidersStatus; nothing in the host calls
/// PrairieAI any more, so the stand-in only has to exist.
actor PrairieAI {
    static let shared = PrairieAI()
}

/// Feature-store refresher; excluded from the host like ``RequestsFeatureStore``.
@MainActor
@Observable
final class SubtitleProvidersStore {
    static let shared = SubtitleProvidersStore()
    private(set) var isAvailable = true
    func reset() { isAvailable = true }
    func refresh() async {}
}

@MainActor
final class RequestsFeatureStore {
    static let shared = RequestsFeatureStore()
    func reset() {}
    func refresh() async {}
}

@MainActor
final class LiveTVFeatureStore {
    static let shared = LiveTVFeatureStore()
    func reset() {}
    func refresh() async {}
}

@MainActor
final class RequestsEventBus {
    static let shared = RequestsEventBus()
    func reset() {}
}

enum DiagLog {
    static func registerSensitiveHost(_ host: String) {}
}

@MainActor
@Observable
final class ConnectionMonitor {
    static let shared = ConnectionMonitor()

    enum ServerStatus {
        case unknown
        case reachable
        case unreachable
    }

    private(set) var isDeviceOnline = true
    private(set) var serverStatus: ServerStatus = .unknown

    var isServerReachable: Bool { isDeviceOnline && serverStatus != .unreachable }
    var isOffline: Bool { !isDeviceOnline || serverStatus == .unreachable }

    func noteServerResponded() {
        serverStatus = .reachable
    }

    func noteServerUnreachable() {
        serverStatus = .unreachable
    }

    /// Same route as the real monitor; HTTPClient treats it as unauthenticated.
    nonisolated static let healthPath = "/api/v1/health"

    /// API v2 contract gate. The host never probes, so no server is flagged.
    var isServerUpdateRequired: Bool { false }

    /// Off-actor read; the host never records a verdict, so always false.
    nonisolated static func readServerUpdateRequired() async -> Bool { false }

    func noteContractProbe(_ result: APIv2ProbeResult, serverId: String) {}
}

/// Referenced by AIModels helpers; real type lives under player subtitles.
struct SidecarSubtitleDescriptor: Hashable {
    var index: Int
    var language: String?
    var codec: String?
    var label: String?
    var source: String
    var forced: Bool
    var url: URL
}

enum SubtitleAIController {
    static func trackKey(for jobId: String) -> String { "ai-\(jobId)" }
}

enum LiveTVChannelListViewModel {
    /// Copied from the production ViewModel helper so LiveTV model tests keep
    /// exercising program schedule math without pulling SwiftUI list code.
    /// Uses the top-level `LiveTVNowNext` from `LiveTVModels.swift`.
    nonisolated static func nowNextMap(
        programs: [LiveTVProgram],
        at now: Date
    ) -> [String: LiveTVNowNext] {
        var grouped: [String: [LiveTVProgram]] = [:]
        for program in programs {
            grouped[program.channelId, default: []].append(program)
        }
        var result: [String: LiveTVNowNext] = [:]
        for (channelId, list) in grouped {
            let sorted = list.sorted { $0.start < $1.start }
            let current = sorted.first { $0.start <= now && now < $0.stop }
            let upcoming: LiveTVProgram?
            if let current {
                upcoming = sorted.first { $0.start >= current.stop }
            } else {
                upcoming = sorted.first { $0.start > now }
            }
            result[channelId] = LiveTVNowNext(now: current, next: upcoming)
        }
        return result
    }

    /// Guide rows omit programmes that have already ended (`stop <= date`).
    nonisolated static func activeOrUpcomingPrograms(
        _ programs: [LiveTVProgram],
        channelId: String,
        at date: Date
    ) -> [LiveTVProgram] {
        programs
            .filter { $0.channelId == channelId && $0.stop > date }
            .sorted { $0.start < $1.start }
    }
}


/// ServerRegistry leaves the active watch party on a server switch; the real
/// session pulls sockets and the player adapter.
@MainActor
final class WatchPartySession {
    static let shared = WatchPartySession()
    func leave(forgetRecent: Bool) {}
    func refreshCapabilities() async {}
}

/// Mirrors the real type in PlaybackSessionBridge.swift, which pulls the
/// player stack. APIv2PlaybackModels maps terminal server failures onto it.
struct PlaybackV3TerminalFailure: LocalizedError, Equatable {
    let reason: String
    let message: String
    let retryable: Bool

    var errorDescription: String? { message }
}

/// Only the destination CalendarModels builds; the full Route enum pulls
/// browse filters and player seeds into the host.
enum Route: Hashable {
    case itemDetail(contentId: String, seriesContext: SeriesDetailContext? = nil)
}

/// Stand-in for the player-side SeekIntervalPreferences; HiddenLibraryPreference
/// only needs the request-identity accessor as a default argument. The real store
/// pulls the player UI and settings transport into the app.
@MainActor
final class SeekIntervalPreferences {
    static func activeRequestIdentity() -> HTTPRequestIdentity? { nil }
}

/// Stand-in for the download session delegate; DownloadModels' attribution path
/// only calls legacyTransferKey, copied verbatim so keys stay faithful. The real
/// class owns the background URLSession.
enum DownloadSessionDelegate {
    static func legacyTransferKey(_ url: URL?) -> String? {
        guard APIv2Client.isDownloadFileURL(url), let url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased() else { return nil }
        let port = parts.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)\(parts.percentEncodedPath)"
    }
}

/// Stand-in for the watch-party lobby policy; WatchPartySocket only needs the
/// path-prefix helper. The real type lives in WatchPartyLobbyState.swift, which
/// pulls the full lobby state machine into the host. basePath copied verbatim.
enum WatchPartyLobbyPolicy {
    /// A server's path prefix in `/a/b` form (empty at the root), ready for
    /// an API or web path to be appended.
    static func basePath(_ percentEncodedPath: String) -> String {
        percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").reduce("") { $0 + "/" + $1 }
    }
}
