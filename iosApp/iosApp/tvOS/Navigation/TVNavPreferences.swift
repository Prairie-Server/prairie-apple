#if os(tvOS)
import Foundation
import Observation

/// Local, per-profile navigation preferences for the Skyline top bar.
///
/// Unlike the server-driven library list (which decides *which* tabs are
/// available), these are user choices about which of those tabs to actually
/// surface. Today there is exactly one: whether the Audiobooks tab appears.
/// It's hidden by default — most users don't listen to audiobooks on the big
/// screen and would rather not see the tab — so the tab is opt-in via
/// Settings. This store is the seam a fuller "customize the header" feature
/// would grow from.
///
/// Storage mirrors `TVLibraryScopeStore`: device-local `SharedDefaults`,
/// keyed per server + profile so two profiles (or two servers) on the same
/// Apple TV keep independent choices. It is intentionally **not** synced to
/// the server, so the preference can differ between this Apple TV and the
/// user's phone — which is the point ("show audiobooks on my phone, not on
/// my TV").
///
/// Unlike `TVLibraryScopeStore` (a value type whose callers drive re-renders
/// by hand), this is an `@Observable` class: the top bar must re-derive its
/// tab list the instant the toggle flips in Settings, so it observes
/// `showAudiobooks` directly.
@Observable
final class TVNavPreferences {
    static let shared = TVNavPreferences()

    /// Whether the Audiobooks tab is shown when an audiobook library exists.
    /// Defaults to `false`: the tab is opt-in.
    private(set) var showAudiobooks: Bool

    @ObservationIgnored private let defaults: SharedDefaults

    init(defaults: SharedDefaults = .shared) {
        self.defaults = defaults
        self.showAudiobooks = Self.readShowAudiobooks(from: defaults)
    }

    /// Persist the choice for the active profile and update the observed
    /// mirror so the top bar re-derives its tabs immediately.
    func setShowAudiobooks(_ value: Bool) {
        showAudiobooks = value
        guard let key = Self.showAudiobooksKey() else { return }
        defaults.set(value, forKey: key)
    }

    /// Re-read the active profile's stored value. Call once the profile is
    /// known: the singleton may still hold the previous profile's value after
    /// a profile switch re-roots the shell, and it's read once at launch
    /// before sign-in (when there is no profile to key on yet).
    func refresh() {
        showAudiobooks = Self.readShowAudiobooks(from: defaults)
    }

    // MARK: - Storage

    private static func readShowAudiobooks(from defaults: SharedDefaults) -> Bool {
        // An absent key reads as `false` (see `SharedDefaults.bool`), which is
        // exactly the opt-in default we want — no presence gate needed.
        guard let key = showAudiobooksKey() else { return false }
        return defaults.bool(forKey: key)
    }

    private static func showAudiobooksKey() -> String? {
        // No profile → nothing to scope. Persisting under an anonymous key
        // would leak one user's choice into the next signed-in profile.
        guard let profileId = AuthService.shared.profileId, !profileId.isEmpty else {
            return nil
        }
        let serverId = ServerRegistry.shared.activeServerId ?? "default"
        return "skyline.nav.showAudiobooks.\(serverId).\(profileId)"
    }
}
#endif
