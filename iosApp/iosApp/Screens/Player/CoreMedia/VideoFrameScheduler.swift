import CoreMedia
import CoreVideo
import Foundation

final class VideoFrameScheduler {
    typealias Frame = (imageBuffer: CVImageBuffer, pts: CMTime)

    private let lock = NSCondition()
    private let queueCap: Int
    private let feedBackpressure: Int
    private var frames: [Frame] = []

    init(queueCap: Int, feedBackpressure: Int) {
        self.queueCap = queueCap
        self.feedBackpressure = feedBackpressure
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
        lock.broadcast()
        lock.unlock()
    }

    func waitUntilBelowFeedBackpressure(isCancelled: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        while frames.count >= feedBackpressure, !isCancelled() {
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
        if frames.count > queueCap {
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
        if !frames.isEmpty { frames.removeFirst() }
        lock.broadcast()
        lock.unlock()
    }

    func popHead() -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        guard !frames.isEmpty else { return nil }
        let frame = frames.removeFirst()
        lock.broadcast()
        return frame
    }
}
