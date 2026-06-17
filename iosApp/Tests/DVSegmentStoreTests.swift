import Foundation

@main
struct DVSegmentStoreTests {
    static func main() {
        testRetiringSpilledSegmentReclaimsSpillBudget()
        testAppendCapacityReflectsCurrentSpillBudget()
        print("DVSegmentStoreTests: all passed")
    }

    private static func testRetiringSpilledSegmentReclaimsSpillBudget() {
        let store = DVSegmentStore(
            generation: UInt64(Date().timeIntervalSince1970 * 1000),
            memoryBudgetBytes: 20,
            spillPolicy: .enabled(reason: "test", maxBytes: 1_000_000)
        )
        let payload = Data(repeating: 0x42, count: 10)

        for index in 0..<10 {
            _ = store.putSegment(
                name: String(format: "seg_%06d.m4s", index),
                data: payload,
                duration: 1
            )
        }

        let before = store.stats()
        precondition(before.tempSpillBytes == 20, "expected two 10-byte spilled segments, got \(before.tempSpillBytes)")
        precondition(before.spilledSegmentCount == 2, "expected two spilled segments, got \(before.spilledSegmentCount)")

        let retired = store.retireSegments(names: ["seg_000000.m4s"])
        precondition(retired == ["seg_000000.m4s"], "expected retired segment name")

        let after = store.stats()
        precondition(after.tempSpillBytes == 10, "retiring a spilled segment must reclaim spill bytes")
        precondition(after.spilledSegmentCount == 1, "retiring a spilled segment must remove its spill entry")

        guard case .gone = store.resource(path: "seg_000000.m4s", waitForNearFuture: false) else {
            preconditionFailure("retired segment should be reported gone")
        }
    }

    private static func testAppendCapacityReflectsCurrentSpillBudget() {
        let store = DVSegmentStore(
            generation: UInt64(Date().timeIntervalSince1970 * 1000) + 1,
            memoryBudgetBytes: 20,
            spillPolicy: .enabled(reason: "test", maxBytes: 20)
        )
        let payload = Data(repeating: 0x42, count: 10)

        for index in 0..<10 {
            _ = store.putSegment(
                name: String(format: "seg_%06d.m4s", index),
                data: payload,
                duration: 1
            )
        }

        precondition(
            !store.canAppendSegment(byteCount: 10),
            "spill-full store should apply backpressure before appending a segment that would require another spill"
        )

        _ = store.retireSegments(names: ["seg_000000.m4s"])
        precondition(
            store.canAppendSegment(byteCount: 10),
            "retiring a spilled segment should free enough spill budget for one more append"
        )
    }
}
