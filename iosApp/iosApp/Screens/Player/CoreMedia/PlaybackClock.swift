//
//  PlaybackClock.swift
//  Continuum (iOS + tvOS)
//

import CoreMedia
import Foundation
import QuartzCore

/// Thread-safe audio-clock plus timeline-anchor state used by `PlayerCore`.
final class PlaybackClock {
    /// Last known audio PTS plus wall-clock stamp, extrapolated forward for a
    /// short window so the playback clock stays smooth between render callbacks.
    struct AudioSnapshot {
        let pts: Double
        let current: Double
        let hasBeenSet: Bool
    }

    private struct AudioState {
        static let maxExtrapolationSeconds: CFTimeInterval = 0.25

        var pts: CMTime = .zero
        var stampedAt: CFTimeInterval = CACurrentMediaTime()
        var hasBeenSet: Bool = false

        func current(rate: Float) -> Double {
            let ptsSeconds = pts.seconds
            guard ptsSeconds.isFinite else { return 0 }
            guard rate != 0 else { return ptsSeconds }
            let elapsed = min(CACurrentMediaTime() - stampedAt, Self.maxExtrapolationSeconds)
            return ptsSeconds + elapsed * Double(rate)
        }

        mutating func update(to newPts: CMTime) {
            pts = newPts
            stampedAt = CACurrentMediaTime()
            hasBeenSet = true
        }
    }

    private let lock = NSLock()
    private var audioState = AudioState()
    private var playbackAnchor = CMTime.zero
    private var playbackAnchorWall = CACurrentMediaTime()
    private var playbackRate: Float = 0

    var rate: Float {
        lock.lock(); defer { lock.unlock() }
        return playbackRate
    }

    func updateAudio(to time: CMTime) {
        lock.lock(); defer { lock.unlock() }
        audioState.update(to: time)
    }

    func audioSnapshot() -> AudioSnapshot {
        lock.lock(); defer { lock.unlock() }
        return AudioSnapshot(
            pts: audioState.pts.seconds,
            current: audioState.current(rate: playbackRate),
            hasBeenSet: audioState.hasBeenSet
        )
    }

    func setTimeline(time: CMTime, rate: Float) {
        lock.lock(); defer { lock.unlock() }
        playbackAnchor = time
        playbackAnchorWall = CACurrentMediaTime()
        playbackRate = rate
    }

    func currentSeconds(prefersAudioClock: Bool) -> Double {
        lock.lock(); defer { lock.unlock() }
        if prefersAudioClock {
            let current = audioState.current(rate: playbackRate)
            if audioState.hasBeenSet, current.isFinite {
                return max(0, current)
            }
        }

        let anchorSeconds = playbackAnchor.seconds
        guard anchorSeconds.isFinite else { return 0 }
        guard playbackRate != 0 else { return max(0, anchorSeconds) }
        let advanced = anchorSeconds + (CACurrentMediaTime() - playbackAnchorWall) * Double(playbackRate)
        return max(0, advanced)
    }
}
