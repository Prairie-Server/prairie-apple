import Foundation

/// Minimal stand-ins for app types that gated Networking code references but
/// that would otherwise pull ContinuumAPI / Diagnostics / player UI into the
/// FFmpeg-free CI host. Full Prairie.app keeps the real implementations.

final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    func clearCachesForServerChange() async {}

    func getProfiles() async throws -> [UserProfile] { [] }
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

enum HTTPError: Error {
    case http(Int, String?)
}

/// Enough of ContinuumAPI for TrackSelectionPersistence fire-and-forget writers.
actor ContinuumAPI {
    static let shared = ContinuumAPI()

    func setAudioPref(seriesId: String, body: AudioPrefRequest) async throws {}
    func setSubtitlePref(seriesId: String, body: SubtitlePrefRequest) async throws {}
    func deleteAudioPref(seriesId: String) async throws {}
    func deleteSubtitlePref(seriesId: String) async throws {}
}

/// Enough of HTTPClient for ServerRegistry + unit-test JSON decoding.
actor HTTPClient {
    static let shared = HTTPClient()

    static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: str) { return date }
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            if let date = whole.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable ISO-8601 date: \(str)"
            )
        }
        return decoder
    }

    func cancelInFlightRequests() async {}
}
