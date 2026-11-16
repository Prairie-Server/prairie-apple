import Foundation

extension Notification.Name {
    static let prairieSessionExpired = Notification.Name("prairieSessionExpired")
    static let prairieProfileVerificationRequired = Notification.Name("prairieProfileVerificationRequired")
    static let temporaryRemoteAuthExpired = Notification.Name("temporaryRemoteAuthExpired")
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
    func requestQueryForImageRequest(_ surface: ArtworkSurface, slotWidthsOnly: Bool = false) async -> [String: String] { [:] }
    func reset() {}
    func refresh(retryFailed: Bool = true) async {}
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

    /// CI stand-in: the update-required verdict never fires in Networking tests.
    nonisolated static func readServerUpdateRequired() async -> Bool { false }

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

/// ServerRegistry resets the on-view card translations on a server switch; the
/// real store drives the AI coordinator from the Home UI.
@MainActor
final class CardDescriptionTranslation {
    static let shared = CardDescriptionTranslation()
    func reset() {}
}

/// DownloadModels matches legacy transfers by this key. The real delegate owns
/// the background URLSession; the key derivation is copied verbatim.
final class DownloadSessionDelegate {
    static func legacyTransferKey(_ url: URL?) -> String? {
        guard APIv2Client.isDownloadFileURL(url), let url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased() else { return nil }
        let port = parts.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)\(parts.percentEncodedPath)"
    }
}

/// HiddenLibraryPreference defaults its request identity to the seek-interval
/// store's; the real store is player UI state. The host has no signed-in
/// profile (`AuthService.profileId` is nil), so there is no active identity.
@MainActor
final class SeekIntervalPreferences {
    static func activeRequestIdentity() -> HTTPRequestIdentity? { nil }
}

/// The real enum (Screens/Auth/NetworkSignIn.swift) also drives the sign-in
/// UI; the v2 client and models only need the API path, copied verbatim.
enum NetworkSignIn {
    static func apiPath(of provider: APIv2AuthProvider) -> String? {
        guard provider.isNetwork else { return nil }
        return ServerAuthPath.relative(provider.networkSignInPath, suffix: ServerAuthPath.networkSignIn,
                                       allowsQuery: false)?.apiPath
    }
}

/// WatchPartySocket joins the server's deployment path with this; the real
/// policy (WatchParty/WatchPartyLobbyState.swift) pulls episode spoiler UI.
enum WatchPartyLobbyPolicy {
    static func basePath(_ percentEncodedPath: String) -> String {
        percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").reduce("") { $0 + "/" + $1 }
    }
}

/// The real type pulls AVFoundation, PlayerSettings and HDR probing; the host
/// only compiles `SubtitleAutoResolver.needsBurnIn`, which needs these two.
enum ApplePlaybackV3Capabilities {
    static func normalizedSubtitleCodec(_ codec: String) -> String { codec.lowercased() }
    static func nativeEmbeddedSubtitleCapabilities(containers: [String]) -> [PlaybackV3NativeEmbeddedSubtitleCapability] { [] }
}

/// LocalRouteController tells the speed scheduler when the route changes; the
/// real scheduler (Screens/Player/BandwidthProbeScheduler.swift) pulls the
/// network-quality monitor and player settings into the host.
@MainActor
final class BandwidthProbeScheduler {
    static let shared = BandwidthProbeScheduler()
    func localRouteChanged() {}
}

/// `APIv2CatalogQuery.sectionItems` reads a section page's target; the real
/// type sits beside the full Route enum (Navigation/Route.swift), which this
/// host stubs above.
struct SectionCatalogTarget: Hashable {
    enum Scope: Hashable {
        case home
        case library(Int)
    }

    let scope: Scope
    let sectionId: String
    let title: String
}

/// ServerRegistry activates the per-account download scope and
/// TrackSelectionPersistence records offline track-pref writes; the real
/// manager (Downloads/DownloadManager.swift) pulls AVFoundation and the
/// download session into the host.
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    @discardableResult
    func activateScopeIfNeeded() async -> Bool { false }

    func noteTrackPrefWrite<Body: TrackPrefBody>(
        _ body: Body?,
        key: String,
        in ledger: WritableKeyPath<TrackPrefsStore, TrackPrefLedger<Body>>,
        auth: CapturedOrdinaryRequestAuth,
        sentAt: Date,
        stored: Bool,
        serverDate: Date?
    ) {}
}

/// ServerMerge folds duplicate servers' download folders together; the real
/// store lives in Downloads/DownloadStore.swift.
actor DownloadStore {
    nonisolated static func mergeScopes(_ scopes: [URL], into destination: URL) -> Bool { true }
}

/// AccountLocalData and ServerMerge clear or move per-account player
/// settings; the real class (Screens/Player/PlayerSettings.swift) is SwiftUI
/// and AVFoundation.
final class PlayerSettings {
    static func purgeLocalData(
        localAccountId: String,
        serverId: String,
        includingLegacy: Bool,
        defaults: UserDefaults = .standard
    ) {}

    static func moveLocalData(
        fromServerURL: String,
        toServerURL: String,
        accounts: Set<String>,
        legacyTarget: String?,
        defaults: UserDefaults = .standard
    ) {}
}

/// CurrentProfileStore checks the decoded-image cache before refetching an
/// avatar; the real cache (Components/Images) needs the platform image stack.
enum PosterImageCache {
    static func cachedVariant(of url: URL, for pixelSize: CGSize) -> (image: AnyObject, isSufficient: Bool)? { nil }
}

/// CurrentProfileStore resolves the avatar URL; copied from
/// Screens/Profiles/ProfileTile.swift, whose views stay out of the host.
enum ProfileAvatarResolver {
    static func serverResolvedImageURL(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()

        // The Nuke pipeline registers no SVG decoder. Legacy presets use an
        // `.svg` extension, while DiceBear uses an `/svg` format path.
        // Decline both and let the caller's raw-ref fallback build a PNG URL.
        // Uploaded avatars are WebP and continue through this path.
        let pathOnly = lowercased.split(separator: "?", maxSplits: 1)[0]
        if pathOnly.hasSuffix(".svg") || pathOnly.hasSuffix("/svg") { return nil }

        if lowercased.hasPrefix("http://")
            || lowercased.hasPrefix("https://")
            || lowercased.hasPrefix("data:image/")
            || lowercased.hasPrefix("file://") {
            return trimmed
        }

        guard trimmed.hasPrefix("/") else { return nil }
        let serverURL = ServerRegistry.shared.activeServerUrl
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !serverURL.isEmpty else { return nil }
        return serverURL + trimmed
    }
}

/// ArtworkSurface sizes the macOS hero; the real theme is SwiftUI.
enum PrairieTheme {
    static func macHeroHeight(forWindowHeight windowHeight: CGFloat) -> CGFloat {
        min(760, max(380, windowHeight * 0.66))
    }
}
