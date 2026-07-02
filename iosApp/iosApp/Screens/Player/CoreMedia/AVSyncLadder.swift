import Foundation

/// Rung selection for the video-behind-audio recovery ladder.
///
/// The display tick's per-frame drop (rung 0) only reaches the decoded
/// queue — at most ~1 s of media. When video falls seconds behind the audio
/// clock (main-thread stall, decode-throughput dip), frame-by-frame dropping
/// recovers at decode speed through the whole packet backlog. The ladder
/// escalates instead: flush the decoded queue in one shot, then skip
/// compressed packets to the next keyframe, and as a last resort re-seek the
/// pipeline to the clock. Pure state machine — the caller performs the
/// selected action — so the escalation rules are unit-testable.
///
/// All inputs come from the display tick (main thread); `wallNow` is passed
/// in so tests control time.
struct AVSyncLadder {
    enum Action: Equatable {
        case none
        /// Rung 1: drop every decoded frame; the next tick renders a frame
        /// near the clock if one decodes in time.
        case flushDecodedFrames
        /// Rung 2: skip compressed packets to the next keyframe and arm a
        /// decoder reset. Recovers a whole GOP at once.
        case dropPacketsToNextKeyframe
        /// Rung 3: full internal seek to the master clock.
        case reseekToClock
    }

    struct Input {
        /// Head-frame PTS minus master clock, seconds (negative = behind).
        var diffSeconds: Double
        var frameDurationSeconds: Double
        var decodedFrameCount: Int
        var packetCount: Int
        var wallNow: Double
    }

    var rung1BehindSeconds = 1.0
    var rung2BehindSeconds = 1.5
    var rung3BehindSeconds = 8.0
    /// Minimum wall-clock spacing between ladder actions so one bad tick
    /// can't fire multiple escalations into a pipeline that hasn't had a
    /// chance to recover.
    var actionCooldownSeconds = 1.0
    /// Rung 3 requires the catastrophic diff to persist this long — a
    /// single wild timestamp must not trigger a full re-seek.
    var rung3SustainSeconds = 1.0

    private var behindRung3Since: Double?
    private var lastActionWall = -Double.infinity
    private var flushedThisEpisode = false

    mutating func evaluate(_ input: Input) -> Action {
        // "Recovered" = back inside the tick's normal drop threshold; the
        // episode ends and rung state re-arms.
        let behindThreshold = -2.0 * input.frameDurationSeconds
        guard input.diffSeconds < behindThreshold else {
            behindRung3Since = nil
            flushedThisEpisode = false
            return .none
        }

        // Rung 3: sustained catastrophic desync.
        if input.diffSeconds <= -rung3BehindSeconds {
            if let since = behindRung3Since {
                if input.wallNow - since >= rung3SustainSeconds,
                   input.wallNow - lastActionWall >= actionCooldownSeconds {
                    lastActionWall = input.wallNow
                    behindRung3Since = nil
                    flushedThisEpisode = false
                    return .reseekToClock
                }
            } else {
                behindRung3Since = input.wallNow
            }
        } else {
            behindRung3Since = nil
        }

        guard input.wallNow - lastActionWall >= actionCooldownSeconds else {
            return .none
        }

        // Rung 2: the decoded queue was already flushed this episode (or is
        // empty because the stall is decode-bound) and there's compressed
        // backlog to skip.
        if input.diffSeconds <= -rung2BehindSeconds,
           input.packetCount > 0,
           flushedThisEpisode || input.decodedFrameCount == 0 {
            lastActionWall = input.wallNow
            return .dropPacketsToNextKeyframe
        }

        // Rung 1: one-shot decoded-queue flush.
        if input.diffSeconds <= -rung1BehindSeconds, input.decodedFrameCount > 0 {
            lastActionWall = input.wallNow
            flushedThisEpisode = true
            return .flushDecodedFrames
        }

        return .none
    }
}
