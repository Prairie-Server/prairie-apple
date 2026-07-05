import XCTest
@testable import Silo

final class LoopbackBridgedDriftGovernorTests: XCTestCase {
    private let rate: Int64 = 48_000
    // 40 ms floor @ 48 kHz.
    private let floor: Int64 = 1_920

    private func feed(
        _ governor: inout LoopbackBridgedDriftGovernor,
        drifts: [Int64],
        startPosition: Int64 = 0
    ) -> [Int64] {
        var position = startPosition
        return drifts.map { drift in
            position += 40 // one TrueHD access unit per observation
            return governor.observe(drift: drift, position: position, sampleRate: rate)
        }
    }

    func testDriftBelowFloorNeverCorrects() {
        var governor = LoopbackBridgedDriftGovernor()
        let out = feed(&governor, drifts: Array(repeating: -floor + 1, count: 100))
        XCTAssertTrue(out.allSatisfy { $0 == 0 })
    }

    func testSustainedEarlyDriftYieldsSilenceFill() {
        var governor = LoopbackBridgedDriftGovernor()
        let out = feed(&governor, drifts: Array(repeating: -3_000, count: 8))
        XCTAssertTrue(out.dropLast().allSatisfy { $0 == 0 })
        XCTAssertEqual(out.last, 3_000, "early content corrects via positive fill")
    }

    func testSustainedLateDriftYieldsTrim() {
        var governor = LoopbackBridgedDriftGovernor()
        let out = feed(&governor, drifts: Array(repeating: 2_500, count: 8))
        XCTAssertEqual(out.last, -2_500, "late content corrects via negative trim")
    }

    func testSpikeDoesNotInflateCorrection() {
        var governor = LoopbackBridgedDriftGovernor()
        // One bogus container timestamp mid-window: correction must size
        // from the minimum sustained magnitude, not the spike.
        var drifts = Array(repeating: Int64(-3_000), count: 8)
        drifts[4] = -90_000
        let out = feed(&governor, drifts: drifts)
        XCTAssertEqual(out.last, 3_000)
    }

    func testSignFlipResetsPersistence() {
        var governor = LoopbackBridgedDriftGovernor()
        var drifts = Array(repeating: Int64(-3_000), count: 7)
        drifts.append(contentsOf: Array(repeating: Int64(3_000), count: 7))
        let out = feed(&governor, drifts: drifts)
        XCTAssertTrue(out.allSatisfy { $0 == 0 }, "neither sign reached 8 consecutive")
    }

    func testPostAnchorFloorTopsUpSeamLeak() {
        var governor = LoopbackBridgedDriftGovernor()
        // 28 ms early-slide @48 kHz: below the 40 ms steady-state floor,
        // above the 5 ms post-anchor floor.
        let leak = Array(repeating: Int64(-1_344), count: 8)
        let steady = feed(&governor, drifts: leak)
        XCTAssertTrue(steady.allSatisfy { $0 == 0 }, "steady floor must ignore a 28 ms leak")
        let topped = leak.enumerated().map { i, d in
            governor.observe(
                drift: d,
                position: Int64((i + 1) * 40),
                sampleRate: rate,
                floorMs: LoopbackBridgedDriftGovernor.postAnchorFloorMs
            )
        }
        XCTAssertEqual(topped.last, 1_344, "post-anchor floor tops the leak up to zero")
    }

    func testCooldownBlocksBackToBackCorrections() {
        var governor = LoopbackBridgedDriftGovernor()
        var out = feed(&governor, drifts: Array(repeating: -3_000, count: 8))
        XCTAssertEqual(out.last, 3_000)
        // Still drifting immediately after: cooldown must swallow it.
        out = feed(&governor, drifts: Array(repeating: -3_000, count: 50), startPosition: 320)
        XCTAssertTrue(out.allSatisfy { $0 == 0 })
        // Past the 10 s cooldown the governor re-arms.
        out = feed(
            &governor,
            drifts: Array(repeating: -3_000, count: 8),
            startPosition: 320 + rate * LoopbackBridgedDriftGovernor.cooldownSeconds
        )
        XCTAssertEqual(out.last, 3_000)
    }
}
