import Foundation

/// Minimal stand-ins for app types that Networking references but that would
/// otherwise pull Diagnostics / Auth / player code into the FFmpeg-free CI host.
///
/// Only the symbols ServerRegistry / ProfilePrefsStore / HTTPClient call are
/// provided. Full Prairie.app keeps the real implementations.

final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    func clearCachesForServerChange() async {}

    func getProfiles() async throws -> [UserProfile] { [] }
}

actor DiagnosticsCoordinator {
    static let shared = DiagnosticsCoordinator()

    nonisolated static func activeProfileWillChange() {}
    nonisolated static func activeProfileDidChange() {}

    func purgeDiagnosticsForCurrentBinding() async -> Bool { false }
    func purgeDiagnosticsForServerRegistryID(_ serverId: String) async {}
}
