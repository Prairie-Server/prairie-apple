import Foundation

@main
struct CompanionDismissalKeyTests {
    static func main() {
        testSameSidStaysDismissed()
        testNewSidIsNotDismissed()
        testMissingSidFallsBackToId()
        testEmptySidBehavesLikeMissing()
        print("CompanionDismissalKeyTests: all passed")
    }

    private static func testSameSidStaysDismissed() {
        var dismissed: Set<String> = []
        dismissed.insert(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionA"))
        precondition(dismissed.contains(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionA")),
                     "the same (id, sid) must remain dismissed")
    }

    private static func testNewSidIsNotDismissed() {
        var dismissed: Set<String> = []
        dismissed.insert(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionA"))
        precondition(!dismissed.contains(CompanionPairingDismissal.key(id: "TV-1", sid: "sessionB")),
                     "a new sid for the same id must re-present (not dismissed)")
    }

    private static func testMissingSidFallsBackToId() {
        precondition(CompanionPairingDismissal.key(id: "TV-1", sid: nil) == "TV-1",
                     "missing sid must key on id alone")
    }

    private static func testEmptySidBehavesLikeMissing() {
        precondition(CompanionPairingDismissal.key(id: "TV-1", sid: "") == "TV-1",
                     "empty sid must behave like missing sid")
    }
}
