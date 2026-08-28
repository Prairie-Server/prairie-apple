import Foundation

extension Notification.Name {
    static let continuumSessionExpired = Notification.Name("continuumSessionExpired")
    static let temporaryRemoteAuthExpired = Notification.Name("temporaryRemoteAuthExpired")
}

/// Minimal stand-ins for app types that gated Networking code references but
/// that would otherwise pull ContinuumAPI / Diagnostics / player UI into the
/// FFmpeg-free CI host. Full Prairie.app keeps the real implementations.

final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    enum SignOutAuthorization: Equatable, Sendable {
        case allowed(account: RefreshAccountIdentity?)
        case refused
    }

    var isLoggedIn: Bool { false }
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

/// ContinuumAPI-backed probe; real type is excluded from the FFmpeg-free host
/// the same way ``AICapabilities`` is. ServerRegistry / ContinuumAPI only need
/// reset/refresh/requestQuery.
final class ImageSizeCapability: @unchecked Sendable {
    static let shared = ImageSizeCapability()
    var requestQuery: [String: String] { [:] }
    func reset() {}
    func refresh() async {}
}

actor ContinuumAI {
    static let shared = ContinuumAI()

    func subtitleProvidersStatus() async throws -> SubtitleProvidersStatus {
        let data = Data("{\"enabled\":true}".utf8)
        return try JSONDecoder().decode(SubtitleProvidersStatus.self, from: data)
    }
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

