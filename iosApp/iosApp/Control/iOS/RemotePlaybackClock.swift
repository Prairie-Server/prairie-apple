#if os(iOS)
import Foundation
import Observation

/// Bridges the ~0.5–1 Hz authoritative TV playback state into a smooth, responsive
/// view model: interpolates `currentTime` between snapshots and lets transport
/// taps reflect instantly (optimistic) until the TV confirms.
@MainActor
@Observable
final class RemotePlaybackClock {
    private(set) var state: SiloControlPlaybackState?
    private var anchorTime: Double = 0
    private var anchorDate = Date(timeIntervalSince1970: 0)

    // Optimistic play/pause: the override wins until a snapshot confirms it
    // or it ages out.
    private var optimisticPlaying: Bool?
    private var optimisticPlayingDate = Date(timeIntervalSince1970: 0)
    private static let optimisticWindow: TimeInterval = 4

    // Optimistic seek: after a local scrub the pinned position wins until the
    // TV's reported time catches up to it (or the window expires), so a stale
    // pre-seek snapshot can't snap the scrubber back.
    private var optimisticTime: Double?
    private var optimisticTimeDate = Date(timeIntervalSince1970: 0)
    private static let optimisticSeekWindow: TimeInterval = 5
    private static let optimisticSeekTolerance: Double = 2.0

    /// Largest backward correction (seconds) that interpolation overrun is
    /// smoothed over instead of snapped. A jump bigger than this is treated as
    /// a genuine seek/loop on the TV and honored immediately.
    private static let maxBackwardSmoothing: Double = 1.5

    func ingest(_ next: SiloControlPlaybackState, asOf now: Date = Date()) {
        let priorDisplay = displayTime(asOf: now)
        state = next

        if let optimisticTime,
           now.timeIntervalSince(optimisticTimeDate) < Self.optimisticSeekWindow,
           abs(next.currentTime - optimisticTime) > Self.optimisticSeekTolerance {
            // Seek not yet reflected by the TV — hold the optimistic anchor so
            // the scrubber stays at the scrubbed position.
        } else {
            optimisticTime = nil
            // Monotonic smoothing: while playing, don't let a snapshot that
            // lags our interpolated position snap the scrubber backward; only
            // a genuine (large) backward jump is honored.
            if isPlaying(asOf: now),
               next.currentTime < priorDisplay,
               priorDisplay - next.currentTime <= Self.maxBackwardSmoothing {
                anchorTime = priorDisplay
            } else {
                anchorTime = next.currentTime
            }
            anchorDate = now
        }

        if let optimisticPlaying, next.isPlaying == optimisticPlaying {
            self.optimisticPlaying = nil    // confirmed
        }
    }

    /// `asOf` is injectable (defaulting to now) so the optimistic-window logic
    /// is deterministic under test instead of reading the wall clock.
    func isPlaying(asOf now: Date = Date()) -> Bool {
        if let optimisticPlaying,
           now.timeIntervalSince(optimisticPlayingDate) < Self.optimisticWindow {
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
        optimisticTime = seconds
        optimisticTimeDate = now
        anchorTime = seconds
        anchorDate = now
    }

    func displayTime(asOf now: Date = Date()) -> Double {
        guard let state else { return 0 }
        guard isPlaying(asOf: now), state.duration > 0 else {
            // Paused / unknown-duration: clamp to [0, duration] when the
            // duration is known so an optimistic seek can't report a position
            // past the end; otherwise just floor at 0.
            let clamped = max(anchorTime, 0)
            return state.duration > 0 ? min(clamped, state.duration) : clamped
        }
        let elapsed = now.timeIntervalSince(anchorDate) * max(state.playbackSpeed, 0.0001)
        return min(anchorTime + elapsed, state.duration)
    }
}
#endif
