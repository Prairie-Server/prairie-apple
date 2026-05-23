import Foundation
import Libavcodec

/// Thread-safe queue of AVPacket pointers. Demuxer thread enqueues; decode
/// threads dequeue. `nil` elements are EOF sentinels — dequeue returns them
/// so the consumer knows to stop requesting.
///
/// Bounded by two independent caps: count and bytes. Enqueue blocks until it
/// can fit under both. `maxBytes == 0` disables the byte cap.
final class PacketQueue {
    private let cond = NSCondition()
    private var storage: [UnsafeMutablePointer<AVPacket>?] = []
    private let capacity: Int
    private let maxBytes: Int
    private var byteCount: Int = 0
    private var closed = false

    init(capacity: Int, maxBytes: Int = 0) {
        self.capacity = capacity
        self.maxBytes = maxBytes
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

    var maxCapacity: Int { capacity }
    var maxByteCapacity: Int { maxBytes }

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
        cond.broadcast()
    }

    func close() {
        cond.lock()
        defer { cond.unlock() }
        closed = true
        cond.broadcast()
    }
}
