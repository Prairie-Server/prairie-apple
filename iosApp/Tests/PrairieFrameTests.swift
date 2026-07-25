import XCTest
import Foundation
@testable import Prairie

final class PrairieFrameTests: XCTestCase {
    func testSingleFrameRoundTrips() {
        let payload = "hello".data(using: .utf8)!
        let framed = try! PrairieFrame.encode(payload)
        var buffer = PrairieFrameBuffer()
        let out = try! buffer.append(framed)
        XCTAssertTrue(out == [payload], "single frame should decode to its payload")
    }

    func testTwoFramesInOneChunk() {
        let a = "aa".data(using: .utf8)!
        let b = "bbbb".data(using: .utf8)!
        var chunk = try! PrairieFrame.encode(a)
        chunk.append(try! PrairieFrame.encode(b))
        var buffer = PrairieFrameBuffer()
        let out = try! buffer.append(chunk)
        XCTAssertTrue(out == [a, b], "two concatenated frames should both decode")
    }

    func testFrameSplitAcrossChunks() {
        let payload = "splitme".data(using: .utf8)!
        let framed = try! PrairieFrame.encode(payload)
        var buffer = PrairieFrameBuffer()
        let first = try! buffer.append(framed.prefix(3))
        XCTAssertTrue(first.isEmpty, "partial frame should yield nothing yet")
        let second = try! buffer.append(framed.suffix(from: framed.index(framed.startIndex, offsetBy: 3)))
        XCTAssertTrue(second == [payload], "completing the frame should yield the payload")
    }

    func testByteAtATimeDripReassembles() {
        let a = "drip".data(using: .utf8)!
        let b = "feed".data(using: .utf8)!
        var wire = try! PrairieFrame.encode(a)
        wire.append(try! PrairieFrame.encode(b))
        var buffer = PrairieFrameBuffer()
        var received: [Data] = []
        for byte in wire {
            received.append(contentsOf: try! buffer.append(Data([byte])))
        }
        XCTAssertTrue(received == [a, b], "byte-at-a-time delivery should reassemble both frames")
    }

    func testZeroLengthFrameYieldsEmptyPayload() {
        let framed = try! PrairieFrame.encode(Data())
        var buffer = PrairieFrameBuffer()
        let out = try! buffer.append(framed)
        XCTAssertTrue(out == [Data()], "a zero-length frame decodes to one empty payload")
    }

    func testOversizeLengthThrows() {
        // 4-byte length header claiming 2 MiB, exceeding maxFrameBytes.
        var length = UInt32(2 << 20).bigEndian
        let header = Data(bytes: &length, count: 4)
        var buffer = PrairieFrameBuffer()
        var threw = false
        do { _ = try buffer.append(header) } catch { threw = true }
        XCTAssertTrue(threw, "an oversize length header must throw")
    }

    func testEncodeRejectsOversizedPayload() {
        let payload = Data(count: PrairieFrame.maxFrameBytes + 1)
        var threw = false
        do { _ = try PrairieFrame.encode(payload) } catch { threw = true }
        XCTAssertTrue(threw, "encoding beyond maxFrameBytes must throw")
    }

    func testExactMaxSizeFrameRoundTrips() {
        let payload = Data(count: PrairieFrame.maxFrameBytes)
        let framed = try! PrairieFrame.encode(payload)
        var buffer = PrairieFrameBuffer()
        let out = try! buffer.append(framed)
        XCTAssertTrue(out == [payload], "a frame exactly at the limit must round-trip")
    }
}
