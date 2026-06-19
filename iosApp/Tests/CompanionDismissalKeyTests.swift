import XCTest
import Foundation
@testable import Silo

final class CompanionDismissalKeyTests: XCTestCase {
    func testSameSidStaysDismissed() {
        var dismissed: Set<String> = []
        dismissed.insert(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionA"))
        XCTAssertTrue(dismissed.contains(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionA")),
                     "the same (id, sid) must remain dismissed")
    }

    func testNewSidIsNotDismissed() {
        var dismissed: Set<String> = []
        dismissed.insert(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionA"))
        XCTAssertFalse(dismissed.contains(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionB")),
                     "a new sid for the same id must re-present (not dismissed)")
    }

    func testMissingSidFallsBackToId() {
        XCTAssertTrue(CompanionPairingDismissal.key(id: "TV-1", sid: nil) == "TV-1",
                     "missing sid must key on id alone")
    }

    func testEmptySidBehavesLikeMissing() {
        XCTAssertTrue(CompanionPairingDismissal.key(id: "TV-1", sid: "") == "TV-1",
                     "empty sid must behave like missing sid")
    }
}
