import Libavcodec
import XCTest
@testable import Prairie

final class PacketQueueTests: XCTestCase {
    /// Allocate a real AVPacket with the given size/duration/key flag. The
    /// queue frees packets it drops/drains; ones we dequeue we free here.
    private func makePacket(size: Int32 = 100, duration: Int64 = 0, key: Bool = false) -> UnsafeMutablePointer<AVPacket> {
        let pkt = av_packet_alloc()!
        XCTAssertEqual(av_new_packet(pkt, size), 0)
        pkt.pointee.duration = duration
        pkt.pointee.flags = key ? AV_PKT_FLAG_KEY : 0
        return pkt
    }

    private func free(_ pkt: UnsafeMutablePointer<AVPacket>?) {
        var p = pkt
        av_packet_free(&p)
    }

    // MARK: - Buffered seconds

    func testBufferedSecondsFromTimedDurations() {
        let queue = PacketQueue(capacity: 100)
        // 1/1000 timebase: duration ticks are milliseconds.
        queue.configureTiming(secondsPerTick: 0.001, fallbackSecondsPerPacket: 0.05)
        queue.enqueue(makePacket(duration: 40))
        queue.enqueue(makePacket(duration: 40))
        queue.enqueue(makePacket(duration: 20))
        XCTAssertEqual(queue.bufferedSeconds, 0.1, accuracy: 1e-9)
        free(queue.dequeue())
        XCTAssertEqual(queue.bufferedSeconds, 0.06, accuracy: 1e-9)
        queue.drain()
        XCTAssertEqual(queue.bufferedSeconds, 0, accuracy: 1e-9)
    }

    func testZeroDurationPacketsUseFallback() {
        let queue = PacketQueue(capacity: 100)
        queue.configureTiming(secondsPerTick: 0.001, fallbackSecondsPerPacket: 0.05)
        queue.enqueue(makePacket(duration: 40))
        queue.enqueue(makePacket(duration: 0))
        queue.enqueue(makePacket(duration: 0))
        // 0.04 timed + 2 × 0.05 fallback.
        XCTAssertEqual(queue.bufferedSeconds, 0.14, accuracy: 1e-9)
    }

    func testUnconfiguredTimingFallsBackToPerPacketEstimateOfZero() {
        let queue = PacketQueue(capacity: 100)
        queue.enqueue(makePacket(duration: 40))
        // Timing unknown → "unknown", reported as 0 rather than a guess.
        XCTAssertEqual(queue.bufferedSeconds, 0, accuracy: 1e-9)
    }

    func testSentinelsDoNotAffectSeconds() {
        let queue = PacketQueue(capacity: 100)
        queue.configureTiming(secondsPerTick: 0.001, fallbackSecondsPerPacket: 0.05)
        queue.enqueue(makePacket(duration: 40))
        queue.enqueue(nil)
        XCTAssertEqual(queue.bufferedSeconds, 0.04, accuracy: 1e-9)
        XCTAssertEqual(queue.count, 2)
    }

    // MARK: - dropToNextKeyframe

    func testDropToNextKeyframeDropsUpToKey() throws {
        let queue = PacketQueue(capacity: 100)
        queue.configureTiming(secondsPerTick: 0.001, fallbackSecondsPerPacket: 0.05)
        queue.enqueue(makePacket(size: 10, duration: 40, key: true))
        queue.enqueue(makePacket(size: 20, duration: 40))
        queue.enqueue(makePacket(size: 30, duration: 40))
        queue.enqueue(makePacket(size: 40, duration: 40, key: true))
        queue.enqueue(makePacket(size: 50, duration: 40))

        let dropped = try XCTUnwrap(queue.dropToNextKeyframe())
        XCTAssertEqual(dropped.count, 3)
        XCTAssertEqual(dropped.seconds, 0.12, accuracy: 1e-9)
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.bufferedSeconds, 0.08, accuracy: 1e-9)

        // Head is now the keyframe.
        let head = try XCTUnwrap(queue.dequeue())
        XCTAssertEqual(head.pointee.flags & AV_PKT_FLAG_KEY, AV_PKT_FLAG_KEY)
        XCTAssertEqual(head.pointee.size, 40)
        free(head)
    }

    func testDropToNextKeyframeNoOpWithoutLaterKeyframe() {
        let queue = PacketQueue(capacity: 100)
        queue.enqueue(makePacket(key: true)) // index 0 doesn't count
        queue.enqueue(makePacket())
        queue.enqueue(makePacket())
        XCTAssertNil(queue.dropToNextKeyframe())
        XCTAssertEqual(queue.count, 3)
    }

    func testDropToNextKeyframeStopsAtEOFSentinel() {
        let queue = PacketQueue(capacity: 100)
        queue.enqueue(makePacket())
        queue.enqueue(nil) // EOF sentinel
        queue.enqueue(makePacket(key: true))
        // The keyframe is past the sentinel — must not drop across it.
        XCTAssertNil(queue.dropToNextKeyframe())
        XCTAssertEqual(queue.count, 3)
    }

    func testDropToNextKeyframeMaintainsByteAccounting() {
        let queue = PacketQueue(capacity: 100)
        queue.enqueue(makePacket(size: 100))
        queue.enqueue(makePacket(size: 200))
        queue.enqueue(makePacket(size: 300, key: true))
        let before = queue.bytes
        XCTAssertEqual(queue.dropToNextKeyframe()?.count, 2)
        // av_new_packet pads sizes; assert relative accounting.
        XCTAssertLessThan(queue.bytes, before)
        let remaining = queue.dequeue()
        XCTAssertEqual(remaining?.pointee.size, 300)
        XCTAssertEqual(queue.bytes, 0)
        free(remaining)
    }

    func testDropToNextKeyframeWakesBlockedEnqueue() {
        // Byte-capped queue: fill it, block a producer, then drop a GOP and
        // require the producer to proceed.
        let queue = PacketQueue(capacity: 100, maxBytes: 1000)
        queue.enqueue(makePacket(size: 400))
        queue.enqueue(makePacket(size: 400))
        queue.enqueue(makePacket(size: 100, key: true))

        let unblocked = expectation(description: "enqueue proceeded")
        DispatchQueue.global().async {
            // 400 bytes won't fit under the 1000-byte cap until the drop.
            queue.enqueue(self.makePacket(size: 400))
            unblocked.fulfill()
        }
        // Give the producer a beat to actually block.
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(queue.dropToNextKeyframe()?.count, 2)
        wait(for: [unblocked], timeout: 5)
        queue.drain()
    }
}
