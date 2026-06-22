import XCTest
@testable import Silo

final class DVSegmentServerRangeTests: XCTestCase {
    func testParsesClosedByteRangeForPartialContent() {
        XCTAssertEqual(
            DVSegmentServer.parseByteRange("bytes=4-9", totalLength: 20),
            .satisfiable(lower: 4, upper: 9)
        )
    }

    func testRejectsUnsatisfiableRange() {
        XCTAssertEqual(
            DVSegmentServer.parseByteRange("bytes=20-30", totalLength: 20),
            .notSatisfiable
        )
    }
}
