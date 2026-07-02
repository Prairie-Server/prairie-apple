import Foundation
import Libavcodec

/// Thread-safe queue of AVPacket pointers. Demuxer thread enqueues; decode
/// threads dequeue. `nil` elements are EOF sentinels — dequeue returns them
/// so the consumer knows to stop requesting.
///
/// Bounded by two independent caps: count and bytes. Enqueue blocks until it
/// can fit under both. `maxBytes == 0` disables the byte cap.
///
/// The queue also tracks buffered media *seconds* from packet durations so
/// buffering policy can be fps/bitrate-independent. Timing is configured at
/// load time via `configureTiming` (stream timebase + a per-packet fallback
/// for containers that emit zero-duration packets).
final class PacketQueue {
    private let cond = NSCondition()
    private var storage: [UnsafeMutablePointer<AVPacket>?] = []
    private let capacity: Int
    private let maxBytes: Int
    private var byteCount: Int = 0
    private var closed = false

    // Buffered-seconds accounting. `durationTicks` sums pkt.duration for
    // packets with a positive duration; packets reporting <= 0 are counted
    // in `zeroDurationCount` and estimated via `fallbackSecondsPerPacket`.
    private var durationTicks: Int64 = 0
    private var zeroDurationCount: Int = 0
    private var secondsPerTick: Double = 0
    private var fallbackSecondsPerPacket: Double = 0

    init(capacity: Int, maxBytes: Int = 0) {
        self.capacity = capacity
        self.maxBytes = maxBytes
    }

    /// Configure duration→seconds conversion once the stream is known.
    /// `secondsPerTick` is the stream timebase (`av_q2d(time_base)`);
    /// `fallbackSecondsPerPacket` estimates packets that report no duration
    /// (video: 1/fps; audio: frame_size/sample_rate or a codec-typical value).
    func configureTiming(secondsPerTick: Double, fallbackSecondsPerPacket: Double) {
        cond.lock()
        self.secondsPerTick = secondsPerTick.isFinite && secondsPerTick > 0 ? secondsPerTick : 0
        self.fallbackSecondsPerPacket = fallbackSecondsPerPacket.isFinite && fallbackSecondsPerPacket > 0
            ? fallbackSecondsPerPacket : 0
        cond.unlock()
    }

    func enqueue(_ pkt: UnsafeMutablePointer<AVPacket>?) {
        cond.lock()
        defer { cond.unlock() }
        if let pkt {
            let size = Int(pkt.pointee.size)
            while !storage.isEmpty, !closed,
                  (storage.count >= capacity || (maxBytes > 0 && byteCount + size > maxBytes)) {
                cond.wait()
            }
            if closed {
                var packet: UnsafeMutablePointer<AVPacket>? = pkt
                av_packet_free(&packet)
                return
            }
            byteCount += size
            addDurationLocked(of: pkt)
            storage.append(pkt)
        } else {
            if closed { return }
            storage.append(nil)
        }
        cond.broadcast()
    }

    func dequeue() -> UnsafeMutablePointer<AVPacket>? {
        cond.lock()
        defer { cond.unlock() }
        while storage.isEmpty, !closed {
            cond.wait()
        }
        if storage.isEmpty { return nil }
        let pkt = storage.removeFirst()
        if let pkt {
            byteCount -= Int(pkt.pointee.size)
            removeDurationLocked(of: pkt)
        }
        cond.broadcast()
        return pkt
    }

    var count: Int {
        cond.lock()
        defer { cond.unlock() }
        return storage.count
    }

    var bytes: Int {
        cond.lock()
        defer { cond.unlock() }
        return byteCount
    }

    /// Estimated seconds of media currently queued. Timed packets use the
    /// configured timebase; zero-duration packets use the fallback estimate.
    /// Before `configureTiming` runs, everything falls back to the per-packet
    /// estimate (which is 0 until configured, i.e. "unknown").
    var bufferedSeconds: Double {
        cond.lock()
        defer { cond.unlock() }
        let timed = secondsPerTick > 0 ? Double(durationTicks) * secondsPerTick : 0
        let untimedPackets = secondsPerTick > 0
            ? zeroDurationCount
            : storage.count
        let untimed = Double(untimedPackets) * fallbackSecondsPerPacket
        return max(0, timed + untimed)
    }

    var maxCapacity: Int { capacity }
    var maxByteCapacity: Int { maxBytes }

    /// Drop queued packets up to (not including) the next keyframe.
    ///
    /// Used by the A/V-sync escalation ladder to skip a GOP when video is
    /// far behind the audio clock. The scan never crosses an EOF sentinel
    /// and requires a keyframe at index >= 1 — on failure it's a strict
    /// no-op, so the queue can never be left starting mid-GOP unless it
    /// already was. Callers must arm a decoder reset before the next
    /// submitted sample (VideoToolbox's DPB is stale after the skip).
    ///
    /// Returns the dropped packet count and their estimated seconds, or nil
    /// when no droppable range exists.
    func dropToNextKeyframe() -> (count: Int, seconds: Double)? {
        cond.lock()
        defer { cond.unlock() }
        var keyIndex: Int?
        for (index, pkt) in storage.enumerated() {
            guard let pkt else { break } // EOF sentinel — never drop past it
            if index == 0 { continue }
            if pkt.pointee.flags & AV_PKT_FLAG_KEY != 0 {
                keyIndex = index
                break
            }
        }
        guard let keyIndex else { return nil }
        var droppedSeconds = 0.0
        for index in 0..<keyIndex {
            guard let pkt = storage[index] else { continue }
            byteCount -= Int(pkt.pointee.size)
            droppedSeconds += secondsLocked(of: pkt)
            removeDurationLocked(of: pkt)
            var packet: UnsafeMutablePointer<AVPacket>? = pkt
            av_packet_free(&packet)
        }
        storage.removeFirst(keyIndex)
        // A demux loop blocked in `enqueue` on the byte budget can proceed.
        cond.broadcast()
        return (keyIndex, droppedSeconds)
    }

    func drain() {
        cond.lock()
        defer { cond.unlock() }
        for pkt in storage {
            if let pkt {
                var packet: UnsafeMutablePointer<AVPacket>? = pkt
                av_packet_free(&packet)
            }
        }
        storage.removeAll(keepingCapacity: true)
        byteCount = 0
        durationTicks = 0
        zeroDurationCount = 0
        cond.broadcast()
    }

    func close() {
        cond.lock()
        defer { cond.unlock() }
        closed = true
        cond.broadcast()
    }

    // MARK: - Duration bookkeeping (callers hold `cond`)

    private func addDurationLocked(of pkt: UnsafeMutablePointer<AVPacket>) {
        let duration = pkt.pointee.duration
        if duration > 0 {
            durationTicks += duration
        } else {
            zeroDurationCount += 1
        }
    }

    private func removeDurationLocked(of pkt: UnsafeMutablePointer<AVPacket>) {
        let duration = pkt.pointee.duration
        if duration > 0 {
            durationTicks -= duration
        } else {
            zeroDurationCount = max(0, zeroDurationCount - 1)
        }
    }

    private func secondsLocked(of pkt: UnsafeMutablePointer<AVPacket>) -> Double {
        let duration = pkt.pointee.duration
        if duration > 0, secondsPerTick > 0 {
            return Double(duration) * secondsPerTick
        }
        return fallbackSecondsPerPacket
    }
}
