#if os(iOS) || os(tvOS)
import AppIntents
import XCTest
@testable import Prairie

/// Siri's in-app search reaches Search through a `prairie://search` link, so a
/// term has to survive the URL round trip unchanged.
@MainActor
final class SiriIntentTests: XCTestCase {
    func testTermSurvivesLinkRoundTrip() throws {
        for term in ["The Office", "Tom & Jerry", "50% off?", "Amélie", "a+b=c #1"] {
            let url = try XCTUnwrap(SiriSearchLink.url(term: term))
            XCTAssertEqual(url.scheme, "prairie")
            XCTAssertEqual(SiriSearchLink.term(from: url), term, "\(url)")
        }
    }

    func testTermIsTrimmedAndBlankOpensEmptySearch() throws {
        XCTAssertEqual(SiriSearchLink.term(from: try XCTUnwrap(URL(string: "prairie://search?q=%20Dune%0A"))), "Dune")
        XCTAssertEqual(SiriSearchLink.term(from: try XCTUnwrap(URL(string: "prairie://search"))), "")
        XCTAssertEqual(SiriSearchLink.term(from: try XCTUnwrap(URL(string: "continuum://search?q=Dune"))), "Dune")
    }

    func testOtherLinksAreNotSearchLinks() throws {
        XCTAssertNil(SiriSearchLink.term(from: try XCTUnwrap(URL(string: "prairie://item/abc?q=Dune"))))
        XCTAssertNil(SiriSearchLink.term(from: try XCTUnwrap(URL(string: "https://search?q=Dune"))))
    }

    func testIntentHandsTermToDeepLinkInbox() async throws {
        let coordinator = PrairieDeepLinkCoordinator.shared
        _ = coordinator.consumePendingURL()
        defer { _ = coordinator.consumePendingURL() }

        let intent = SearchInPrairieIntent()
        intent.criteria = StringSearchCriteria(term: "Blade Runner")
        _ = try await intent.perform()

        let url = try XCTUnwrap(coordinator.consumePendingURL())
        XCTAssertEqual(SiriSearchLink.term(from: url), "Blade Runner")
    }
}
#endif
