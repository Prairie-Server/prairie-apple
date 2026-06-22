import XCTest
@testable import Silo

final class TrueHDPrimingPolicyTests: XCTestCase {
    func testTailPolicyDropsOldestPacketWhenPacketCapWouldBeExceeded() {
        let dropCount = DVPreVideoAudioTailPolicy.headDropCountBeforeAppending(
            existingByteSizes: [10, 10, 10],
            retainedBytes: 30,
            incomingBytes: 10,
            maxPackets: 3,
            maxBytes: 100
        )

        XCTAssertEqual(dropCount, 1)
    }

    func testTailPolicyDropsOldestPacketsUntilByteCapAllowsIncomingPacket() {
        let dropCount = DVPreVideoAudioTailPolicy.headDropCountBeforeAppending(
            existingByteSizes: [4, 4, 4],
            retainedBytes: 12,
            incomingBytes: 4,
            maxPackets: 10,
            maxBytes: 10
        )

        XCTAssertEqual(dropCount, 2)
    }

    func testTailPolicyRejectsPacketLargerThanByteCap() {
        let dropCount = DVPreVideoAudioTailPolicy.headDropCountBeforeAppending(
            existingByteSizes: [2, 2],
            retainedBytes: 4,
            incomingBytes: 11,
            maxPackets: 10,
            maxBytes: 10
        )

        XCTAssertNil(dropCount)
    }

    func testTrueHDMajorSyncScannerFindsSyncInRetainedBytes() {
        let retainedTail = Data([0x00, 0x11, 0x22, 0xF8, 0x72, 0x6F, 0xBA, 0x33])

        XCTAssertTrue(DVTrueHDMajorSyncScanner.containsMajorSync(retainedTail))
    }
}
