import XCTest
@testable import Prairie

/// An empty calendar week links to the other two views, never the one on
/// screen (issue #513, matching the Web empty state).
final class CalendarFilterTests: XCTestCase {
    func testEmptyStateLinksToTheOtherTwoViews() {
        XCTAssertEqual(CalendarFilter.following.emptyStateLinks, [.trending, .everything])
        XCTAssertEqual(CalendarFilter.trending.emptyStateLinks, [.following, .everything])
        XCTAssertEqual(CalendarFilter.everything.emptyStateLinks, [.following, .trending])
    }
}
