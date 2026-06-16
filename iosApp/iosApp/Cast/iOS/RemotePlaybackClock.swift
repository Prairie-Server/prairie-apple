#if os(iOS)
import Foundation
import Observation

/// Bridges the ~0.5–1 Hz authoritative cast state into a smooth, responsive
/// view model: interpolates `currentTime` between snapshots and lets transport
/// taps reflect instantly (optimistic) until the TV confirms.
@MainActor
@Observable
final class RemotePlaybackClock {
    private(set) var state: SiloCastPlaybackState?
    private var anchorTime: Double = 0
    private var anchorDate = Date(timeIntervalSince1970: 0)

    // Optimistic play/pause: the override wins until a snapshot confirms it
    // or it ages out.
    private var optimisticPlaying: Bool?
    private var optimisticPlayingDate = Date(timeIntervalSince1970: 0)
    private static let optimisticWindow: TimeInterval = 4

    func ingest(_ next: SiloCastPlaybackState, asOf now: Date = Date()) {
        state = next
        anchorTime = next.currentTime
        anchorDate = now
        if let optimisticPlaying, next.isPlaying == optimisticPlaying {
            self.optimisticPlaying = nil    // confirmed
        }
    }

    var isPlaying: Bool {
        if let optimisticPlaying,
           Date().timeIntervalSince(optimisticPlayingDate) < Self.optimisticWindow {
            return optimisticPlaying
        }
        return state?.isPlaying ?? false
    }

    func setOptimisticPlaying(_ playing: Bool, asOf now: Date = Date()) {
        optimisticPlaying = playing
        optimisticPlayingDate = now
        // Re-anchor so interpolation reflects the new direction immediately.
        anchorTime = displayTime(asOf: now)
        anchorDate = now
    }

    /// Pin the playhead after a local seek so the slider doesn't snap back to a
    /// stale snapshot before the next state arrives.
    func setOptimisticTime(_ seconds: Double, asOf now: Date = Date()) {
        anchorTime = seconds
        anchorDate = now
    }

    func displayTime(asOf now: Date = Date()) -> Double {
        guard let state else { return 0 }
        guard isPlaying, state.duration > 0 else {
            return min(max(anchorTime, 0), max(state.duration, anchorTime))
        }
        let elapsed = now.timeIntervalSince(anchorDate) * max(state.playbackSpeed, 0.0001)
        return min(anchorTime + elapsed, state.duration)
    }
}
#endif
