import Foundation
import XCTest
@testable import Prairie

/// The shared metadata flights over the real `PrairieAPI` → `APIv2Client` →
/// `HTTPClient` stack: concurrent reads of one item share a request, reads
/// for different items or a finished flight do not, and a cancelled sole
/// waiter stops its flight.
final class MetadataRequestPoolTests: XCTestCase {
    private var stub = APIv2TestStub()

    override func setUp() {
        super.setUp()
        stub = APIv2TestStub()
    }

    private func pool() async throws -> MetadataRequestPool {
        let name = "MetadataRequestPoolTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let tokens = TokenStore(keychain: SharedKeychain(service: name, accessGroup: nil),
            defaults: SharedDefaults(suite: suite, standard: suite))
        await tokens.switchActiveServer(serverId: "metadata-pool-test")
        await tokens.setServerUrl("https://metadata.example")
        await tokens.setProfileId("profile-one")
        let http = HTTPClient(session: stub.makeSession(), tokenStore: tokens)
        return MetadataRequestPool(api: PrairieAPI(http: http, tokenStore: tokens), tokenStore: tokens)
    }

    private static func item(_ id: String) -> String {
        #"""
        {"content_id":"\#(id)","type":"movie","status":"available","title":"Title \#(id)",
         "cast":[],"crew":[],"genres":[],"keywords":[],"subtitles":[],"versions":[]}
        """#
    }

    func testConcurrentItemReadsShareOneRequest() async throws {
        let pool = try await pool()
        stub.reply(200, Self.item("movie:1"))
        stub.hold()
        async let first = pool.itemDetail(contentId: "movie:1")
        await stub.waitUntilHeld()
        async let second = pool.itemDetail(contentId: "movie:1")
        // Give the second caller time to join the parked flight.
        try await Task.sleep(nanoseconds: 50_000_000)
        stub.release()
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.title, "Title movie:1")
        XCTAssertEqual(b.contentId, "movie:1")
        XCTAssertEqual(stub.requests.count, 1)
        XCTAssertTrue(stub.requestedPaths.first?.hasPrefix("/api/v2/catalog/items/") == true)

        // A finished flight is not a cache.
        _ = try await pool.itemDetail(contentId: "movie:1")
        XCTAssertEqual(stub.requests.count, 2)

        // A freshness discriminator or another item is its own flight.
        stub.reply(200, Self.item("movie:2"))
        let other = try await pool.itemDetail(contentId: "movie:2", freshnessDiscriminator: "rev-2")
        XCTAssertEqual(other.contentId, "movie:2")
        XCTAssertEqual(stub.requests.count, 3)
    }

    func testSeasonEpisodeAndWatchReads() async throws {
        let pool = try await pool()
        stub.reply(200, #"""
        {"items":[{"content_id":"season:1","episode_count":2,"season_number":1,"title":"Season 1"}],
         "page":{"has_more":false}}
        """#)
        let seasons = try await pool.seasons(seriesId: "series:1")
        XCTAssertEqual(seasons.seasons.map(\.seasonNumber), [1])

        stub.reply(200, #"""
        {"items":[{"content_id":"episode:1","episode_number":1,"runtime":30,"season_number":1,"title":"Pilot"}],
         "page":{"has_more":false}}
        """#)
        let episodes = try await pool.episodes(seriesId: "series:1", seasonNumber: 1, libraryId: 4)
        XCTAssertEqual(episodes.episodes.map(\.title), ["Pilot"])

        stub.reply(200, #"""
        {"content_id":"episode:1","type":"episode","title":"Pilot","versions":[],"subtitles":[]}
        """#)
        let watch = try await pool.watchDetail(contentId: "episode:1")
        XCTAssertEqual(watch.title, "Pilot")
        XCTAssertEqual(stub.requests.count, 3)
    }

    func testCancelledSoleWaiterStopsItsFlight() async throws {
        let pool = try await pool()
        stub.reply(200, Self.item("movie:3"))
        stub.hold()
        let task = Task { try await pool.itemDetail(contentId: "movie:3") }
        await stub.waitUntilHeld()
        task.cancel()
        stub.release()
        do {
            _ = try await task.value
            XCTFail("a cancelled read must not deliver a value")
        } catch {
            // Cancellation surfaces as CancellationError or a cancelled transport.
        }

        // The cancelled flight is gone, so the next read dispatches again.
        stub.reply(200, Self.item("movie:3"))
        let again = try await pool.itemDetail(contentId: "movie:3")
        XCTAssertEqual(again.contentId, "movie:3")
        XCTAssertEqual(stub.requests.count, 2)
    }
}
