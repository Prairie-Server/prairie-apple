import Foundation

/// Hysteresis-based rebuffer detector for the CoreMedia engine.
///
/// Buffer depth is measured in *seconds* per track (packet-queue seconds
/// plus decoded/rendered-side seconds), min across active tracks, so the
/// policy behaves the same for 24 fps SD and 60 fps 4K. The enter and leave
/// thresholds are deliberately far apart: entering requires near-starvation,
/// leaving requires a real cushion, so the state can't flap while hovering
/// at a boundary the way a single packet-count threshold can.
struct BufferingPolicy {
    struct Sample {
        /// Buffered seconds for the video track, nil when no video stream.
        var videoBufferedSeconds: Double?
        /// Buffered seconds for the audio track, nil when no audio stream.
        var audioBufferedSeconds: Double?
        /// Whether the audio renderer is asking for media it can't get.
        /// nil when no audio stream — starvation alone then decides, so
        /// video-only files can still surface a stall.
        var audioRendererHungry: Bool?
        var isPlaying: Bool
        /// Input EOF reached: the remaining media is all we'll ever have,
        /// so a shrinking buffer is drain-out, not a stall.
        var reachedInputEOF: Bool
        /// Within the post-seek fast-resume window: leave threshold halves
        /// so seeks recover faster than steady-state rebuffers.
        var withinPostSeekWindow: Bool
    }

    /// Near-starvation floor to *enter* buffering.
    var enterThresholdSeconds = 0.2
    /// Cushion required to *leave* buffering in steady state.
    var leaveThresholdSeconds = 3.0
    /// Cushion required to leave buffering shortly after a user seek.
    var leaveThresholdAfterSeekSeconds = 1.5

    private(set) var isBuffering = false

    /// Buffered seconds from the last evaluated sample (min across tracks);
    /// nil when no track reported. Drives the buffering-progress callback.
    private(set) var lastMinBufferedSeconds: Double?

    var activeLeaveThresholdSeconds: Double {
        lastSampleWasPostSeek ? leaveThresholdAfterSeekSeconds : leaveThresholdSeconds
    }

    private var lastSampleWasPostSeek = false

    @discardableResult
    mutating func evaluate(_ sample: Sample) -> Bool {
        lastSampleWasPostSeek = sample.withinPostSeekWindow
        let tracked = [sample.videoBufferedSeconds, sample.audioBufferedSeconds]
            .compactMap { $0 }
            .filter { $0.isFinite }
        lastMinBufferedSeconds = tracked.min()

        guard sample.isPlaying, !sample.reachedInputEOF, let minBuffered = tracked.min() else {
            isBuffering = false
            return isBuffering
        }

        if isBuffering {
            let leave = sample.withinPostSeekWindow
                ? leaveThresholdAfterSeekSeconds
                : leaveThresholdSeconds
            if minBuffered >= leave {
                isBuffering = false
            }
        } else {
            // Starvation plus (when audio exists) a renderer actually asking
            // for media. The hungry check suppresses "at capacity but idle"
            // noise; with no audio stream, starvation alone decides.
            if minBuffered < enterThresholdSeconds, sample.audioRendererHungry ?? true {
                isBuffering = true
            }
        }
        return isBuffering
    }
}
