import Foundation
import Observation

/// Cached holder for Live TV availability, gating the Live TV tab on iOS and
/// the Live TV root on tvOS.
///
/// Follows `RequestsFeatureStore`: a `@MainActor` `@Observable` singleton,
/// probed once per session and reset on profile/server switch. The probe
/// lists channels; the tab appears when the server returns at least one
/// enabled channel. A 404 (older server without Live TV) or any transient
/// error reads as "disabled" on the first probe so entry points never render
/// and no error surfaces.
@MainActor
@Observable
final class LiveTVFeatureStore {
    static let shared = LiveTVFeatureStore()

    /// False until a successful probe reports at least one enabled channel.
    private(set) var isEnabled = false

    /// Bumped on every `reset()` so a probe that finishes after a sign-out
    /// or profile switch discards its result.
    private var generation = 0

    private let api: ContinuumAPI

    init(api: ContinuumAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        let gen = generation
        let channels = try? await api.liveTVChannels()
        guard gen == generation else { return }
        if let channels {
            isEnabled = channels.contains(where: \.enabled)
        }
        // On error, keep the previous value: a transient failure shouldn't
        // yank an already-visible tab, and foreground/auth-state transitions
        // retry naturally.
    }

    func reset() {
        generation &+= 1
        isEnabled = false
    }
}
