import XCTest
@testable import Silo

final class HDR10PlusSEIDetectorTests: XCTestCase {
    /// ITU-T T.35 header for SMPTE ST 2094-40 (HDR10+) dynamic metadata.
    private let needle: [UInt8] = [0xB5, 0x00, 0x3C, 0x00, 0x01, 0x04]
    /// Filler byte chosen so no window across filler + needle boundaries can
    /// form an accidental second needle (0xAA never appears in the needle).
    private let filler: UInt8 = 0xAA

    func testDetectsNeedleAtBufferStart() {
        var detector = HDR10PlusSEIDetector()
        let buffer = Data(needle + [UInt8](repeating: filler, count: 16))
        XCTAssertTrue(detector.scan(buffer))
        XCTAssertTrue(detector.detected)
    }

    func testDetectsNeedleAtBufferEnd() {
        var detector = HDR10PlusSEIDetector()
        let buffer = Data([UInt8](repeating: filler, count: 16) + needle)
        XCTAssertTrue(detector.scan(buffer))
        XCTAssertTrue(detector.detected)
    }

    func testDetectsNeedleAtArbitraryOffsets() {
        for offset in 1...8 {
            var detector = HDR10PlusSEIDetector()
            let buffer = Data(
                [UInt8](repeating: filler, count: offset)
                    + needle
                    + [UInt8](repeating: filler, count: 8)
            )
            XCTAssertTrue(detector.scan(buffer), "needle missed at offset \(offset)")
            XCTAssertTrue(detector.detected)
        }
    }

    func testIgnoresBufferWithoutNeedle() {
        var detector = HDR10PlusSEIDetector()
        XCTAssertFalse(detector.scan(Data([UInt8](repeating: filler, count: 64))))
        XCTAssertFalse(detector.detected)
    }

    func testIgnoresNearMissLastByte() {
        var detector = HDR10PlusSEIDetector()
        var nearMiss = needle
        nearMiss[nearMiss.count - 1] = 0x05
        let buffer = Data([UInt8](repeating: filler, count: 4) + nearMiss)
        XCTAssertFalse(detector.scan(buffer))
        XCTAssertFalse(detector.detected)
    }

    func testIgnoresNeedleTruncatedAtBufferEnd() {
        var detector = HDR10PlusSEIDetector()
        let buffer = Data([UInt8](repeating: filler, count: 8) + needle.dropLast())
        XCTAssertFalse(detector.scan(buffer))
        XCTAssertFalse(detector.detected)
    }

    func testIgnoresBuffersShorterThanNeedle() {
        for count in 0..<needle.count {
            var detector = HDR10PlusSEIDetector()
            XCTAssertFalse(detector.scan(Data(needle.prefix(count))))
            XCTAssertFalse(detector.detected)
        }
    }

    func testLatchesAfterFirstHit() {
        var detector = HDR10PlusSEIDetector()
        let buffer = Data([UInt8](repeating: filler, count: 4) + needle)
        XCTAssertTrue(detector.scan(buffer))
        // A second needle-bearing packet must NOT re-fire: the writer's
        // one-shot callback contract depends on the latch.
        XCTAssertFalse(detector.scan(buffer))
        XCTAssertTrue(detector.detected)
    }

    // MARK: - NAL-walked packet scan

    /// Length-prefixed NAL unit (4-byte length) with an HEVC NAL header for
    /// the given type followed by `payload`.
    private func hevcNAL(type: UInt8, payload: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [type << 1, 0x01] + payload
        let len = UInt32(body.count)
        return [
            UInt8(len >> 24 & 0xFF), UInt8(len >> 16 & 0xFF),
            UInt8(len >> 8 & 0xFF), UInt8(len & 0xFF),
        ] + body
    }

    private func scanPacket(_ detector: inout HDR10PlusSEIDetector, _ packet: [UInt8], isHEVC: Bool = true) -> Bool {
        packet.withUnsafeBufferPointer { buffer in
            detector.scanVideoPacket(
                bytes: buffer.baseAddress!,
                count: buffer.count,
                nalLengthSize: 4,
                isHEVC: isHEVC
            )
        }
    }

    func testFindsNeedleInsidePrefixSEINAL() {
        var detector = HDR10PlusSEIDetector()
        let packet = hevcNAL(type: 32, payload: [UInt8](repeating: filler, count: 32))
            + hevcNAL(type: 39, payload: [0x04, 0x30] + needle + [0x80])
            + hevcNAL(type: 19, payload: [UInt8](repeating: filler, count: 64))
        XCTAssertTrue(scanPacket(&detector, packet))
        XCTAssertTrue(detector.detected)
    }

    func testIgnoresNeedleInsideNonSEINAL() {
        // The needle bytes appearing inside slice data must not fire the
        // badge — only SEI payloads are scanned.
        var detector = HDR10PlusSEIDetector()
        let packet = hevcNAL(type: 19, payload: [UInt8](repeating: filler, count: 16) + needle)
        XCTAssertFalse(scanPacket(&detector, packet))
        XCTAssertFalse(detector.detected)
    }

    func testMalformedNALWalkFallsBackToRawScan() {
        var detector = HDR10PlusSEIDetector()
        // Declared NAL length overruns the packet: the walker cannot parse,
        // so the remainder is raw-scanned and the needle still detected.
        let packet: [UInt8] = [0x7F, 0xFF, 0xFF, 0xFF] + [UInt8](repeating: filler, count: 8) + needle
        XCTAssertTrue(scanPacket(&detector, packet))
        XCTAssertTrue(detector.detected)
    }

    func testScanBudgetDisarmsDetector() {
        var detector = HDR10PlusSEIDetector()
        let plain = hevcNAL(type: 19, payload: [UInt8](repeating: filler, count: 32))
        for _ in 0..<HDR10PlusSEIDetector.scanBudgetPackets {
            XCTAssertFalse(scanPacket(&detector, plain))
        }
        XCTAssertFalse(detector.isActive)
        // Past the budget even a genuine SEI needle is ignored — the
        // detector has concluded the stream is not HDR10+ and stops paying
        // for scans (plain-HDR10 films otherwise scan every packet forever).
        let sei = hevcNAL(type: 39, payload: [0x04, 0x30] + needle)
        XCTAssertFalse(scanPacket(&detector, sei))
        XCTAssertFalse(detector.detected)
    }

    func testH264SEINALIsScanned() {
        var detector = HDR10PlusSEIDetector()
        let body: [UInt8] = [0x06, 0x04] + needle  // NAL type 6 (SEI)
        let len = UInt32(body.count)
        let packet: [UInt8] = [
            UInt8(len >> 24 & 0xFF), UInt8(len >> 16 & 0xFF),
            UInt8(len >> 8 & 0xFF), UInt8(len & 0xFF),
        ] + body
        XCTAssertTrue(scanPacket(&detector, packet, isHEVC: false))
        XCTAssertTrue(detector.detected)
    }
}
