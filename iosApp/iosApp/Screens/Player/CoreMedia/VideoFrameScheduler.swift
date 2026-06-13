import CoreMedia
import CoreVideo
import Foundation

final class VideoFrameScheduler {
    typealias Frame = (imageBuffer: CVImageBuffer, pts: CMTime)

    private let lock = NSCondition()
    private let queueCap: Int
    private let feedBackpressure: Int
    /// Byte ceiling for the decoded queue's feed backpressure. Decoded 4K
    /// 10-bit frames are ~25 MiB of IOSurface each, so a pure frame-count
    /// threshold tuned for 1080p can pin hundreds of MiB on big formats —
    /// enough to matter against jetsam on 3 GiB Apple TVs. The feed loop
    /// parks when EITHER the count or the byte threshold is reached; small
    /// formats stay count-bound and see no behavior change.
    private let feedBackpressureBytes: Int
    private var frames: [Frame] = []
    private var queuedBytes = 0

    init(queueCap: Int, feedBackpressure: Int, feedBackpressureBytes: Int = .max) {
        self.queueCap = queueCap
        self.feedBackpressure = feedBackpressure
        self.feedBackpressureBytes = feedBackpressureBytes
    }

    var count: Int {
        lock.lock()
        let count = frames.count
        lock.unlock()
        return count
    }

    func wakeWaiters() {
        lock.lock()
        lock.broadcast()
        lock.unlock()
    }

    func removeAll(keepingCapacity: Bool = false) {
        lock.lock()
        frames.removeAll(keepingCapacity: keepingCapacity)
        queuedBytes = 0
        lock.broadcast()
        lock.unlock()
    }

    func waitUntilBelowFeedBackpressure(isCancelled: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        while frames.count >= feedBackpressure || queuedBytes >= feedBackpressureBytes,
              !isCancelled() {
            lock.wait()
        }
        return !isCancelled()
    }

    /// VT delivers frames in decode order, so B-frame content must be inserted
    /// by PTS. The queue head is always the next presentation candidate.
    func insertSorted(imageBuffer: CVImageBuffer, pts: CMTime) {
        lock.lock()
        let ptsSeconds = pts.seconds
        if let last = frames.last, ptsSeconds >= last.pts.seconds {
            frames.append((imageBuffer, pts))
        } else if let insertAt = frames.firstIndex(where: { $0.pts.seconds > ptsSeconds }) {
            frames.insert((imageBuffer, pts), at: insertAt)
        } else {
            frames.append((imageBuffer, pts))
        }
        queuedBytes += Self.approximateBytes(of: imageBuffer)
        if frames.count > queueCap {
            for overflow in frames.suffix(frames.count - queueCap) {
                queuedBytes -= Self.approximateBytes(of: overflow.imageBuffer)
            }
            frames.removeLast(frames.count - queueCap)
        }
        lock.unlock()
    }

    func peek() -> Frame? {
        lock.lock()
        let frame = frames.first
        lock.unlock()
        return frame
    }

    func dropHead() {
        lock.lock()
        if !frames.isEmpty {
            let frame = frames.removeFirst()
            queuedBytes -= Self.approximateBytes(of: frame.imageBuffer)
        }
        lock.broadcast()
        lock.unlock()
    }

    func popHead() -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        guard !frames.isEmpty else { return nil }
        let frame = frames.removeFirst()
        queuedBytes -= Self.approximateBytes(of: frame.imageBuffer)
        lock.broadcast()
        return frame
    }

    /// IOSurface-backed VT output usually reports its real allocation via
    /// `CVPixelBufferGetDataSize`; GPU-only buffers can report 0, so fall
    /// back to a bi-planar 4:2:0 estimate from the pixel dimensions.
    private static func approximateBytes(of buffer: CVImageBuffer) -> Int {
        let reported = CVPixelBufferGetDataSize(buffer)
        if reported > 0 { return reported }
        return CVPixelBufferGetWidth(buffer) * CVPixelBufferGetHeight(buffer) * 3 / 2
    }
}
