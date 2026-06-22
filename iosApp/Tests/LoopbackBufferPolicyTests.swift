import XCTest
@testable import Silo

final class LoopbackBufferPolicyTests: XCTestCase {
    func testGeneratedMediaBitrateDrivesSteadyStateBufferTarget() {
        let target = AVPlayerBackend.loopbackSteadyStateForwardBufferTarget(
            forBitsPerSecond: 69_000_000,
            targetDuration: 4,
            longestSegmentDuration: 4,
            constrainedMemoryDevice: true
        )

        XCTAssertGreaterThan(target, 18)
        XCTAssertLessThan(target, 21)
    }

    func testLiveEdgeFloorAppliesWhenBitrateIsUnknown() {
        let target = AVPlayerBackend.loopbackSteadyStateForwardBufferTarget(
            forBitsPerSecond: nil,
            targetDuration: 6,
            longestSegmentDuration: 10,
            constrainedMemoryDevice: true
        )

        XCTAssertEqual(target, 28)
    }
}
