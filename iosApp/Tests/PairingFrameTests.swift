import Foundation

@main
struct PairingFrameTests {
    static func main() {
        testSingleFrameRoundTrips()
        testTwoFramesInOneChunk()
        testFrameSplitAcrossChunks()
        testOversizeLengthThrows()
        print("PairingFrameTests: all passed")
    }

    private static func testSingleFrameRoundTrips() {
        let payload = "hello".data(using: .utf8)!
        let framed = try! PairingFrame.encode(payload)
        var buffer = PairingFrameBuffer()
        let out = try! buffer.append(framed)
        precondition(out == [payload], "single frame should decode to its payload")
    }

    private static func testTwoFramesInOneChunk() {
        let a = "aa".data(using: .utf8)!
        let b = "bbbb".data(using: .utf8)!
        var chunk = try! PairingFrame.encode(a)
        chunk.append(try! PairingFrame.encode(b))
        var buffer = PairingFrameBuffer()
        let out = try! buffer.append(chunk)
        precondition(out == [a, b], "two concatenated frames should both decode")
    }

    private static func testFrameSplitAcrossChunks() {
        let payload = "splitme".data(using: .utf8)!
        let framed = try! PairingFrame.encode(payload)
        var buffer = PairingFrameBuffer()
        let first = try! buffer.append(framed.prefix(3))
        precondition(first.isEmpty, "partial frame should yield nothing yet")
        let second = try! buffer.append(framed.suffix(from: framed.index(framed.startIndex, offsetBy: 3)))
        precondition(second == [payload], "completing the frame should yield the payload")
    }

    private static func testOversizeLengthThrows() {
        // 4-byte length header claiming 2 MiB, exceeding maxFrameBytes.
        var length = UInt32(2 << 20).bigEndian
        let header = Data(bytes: &length, count: 4)
        var buffer = PairingFrameBuffer()
        var threw = false
        do { _ = try buffer.append(header) } catch { threw = true }
        precondition(threw, "an oversize length header must throw")
    }
}
