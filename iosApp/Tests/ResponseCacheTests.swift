//
//  ResponseCacheTests.swift
//  PrairieTests
//

import XCTest
@testable import Prairie

@MainActor
final class ResponseCacheTests: XCTestCase {

    override func setUp() async throws {
        ResponseCache.shared.clearAll()
    }

    override func tearDown() async throws {
        ResponseCache.shared.clearAll()
    }

    func testSetGetRemove() {
        let cache = ResponseCache.shared
        cache.set("hello", for: "k1")
        XCTAssertEqual(cache.get("k1", as: String.self), "hello")
        XCTAssertNil(cache.get("k1", as: Int.self))
        cache.remove("k1")
        XCTAssertNil(cache.get("k1", as: String.self))
    }

    func testUpdateInPlace() {
        let cache = ResponseCache.shared
        cache.set(1, for: "n")
        cache.update("n", as: Int.self) { $0 += 41 }
        XCTAssertEqual(cache.get("n", as: Int.self), 42)
        cache.update("missing", as: Int.self) { $0 += 1 }
        XCTAssertNil(cache.get("missing", as: Int.self))
    }

    func testRemoveAllWithPrefixAndInvalidateItemMetadata() {
        let cache = ResponseCache.shared
        cache.set(true, for: CacheKey.itemDetail("1"))
        cache.set(true, for: CacheKey.itemSeasons("1"))
        cache.set(true, for: CacheKey.homeSections)
        cache.set(true, for: CacheKey.recommendations)
        cache.set(true, for: CacheKey.adminStats)

        cache.invalidateAllItemMetadata()
        XCTAssertNil(cache.get(CacheKey.itemDetail("1"), as: Bool.self))
        XCTAssertNil(cache.get(CacheKey.itemSeasons("1"), as: Bool.self))
        XCTAssertNil(cache.get(CacheKey.homeSections, as: Bool.self))
        XCTAssertNil(cache.get(CacheKey.recommendations, as: Bool.self))
        XCTAssertEqual(cache.get(CacheKey.adminStats, as: Bool.self), true)
    }

    func testCacheKeyBuilders() {
        XCTAssertEqual(CacheKey.browse(libraryId: 3, filterKey: "g:action"), "browse:3:g:action")
        XCTAssertEqual(CacheKey.browse(libraryId: nil, filterKey: "all"), "browse:all:all")
        XCTAssertEqual(CacheKey.catalogFilters(libraryId: 1, includeTechnical: false), "catalogFilters:1:basic")
        XCTAssertEqual(CacheKey.tvLibrary(libraryId: 9, filterKey: "x"), "tvlibrary:9:x")
        XCTAssertEqual(CacheKey.calendarWeek("2026-01-01", filter: "all"), "calendar:2026-01-01:all")
        XCTAssertFalse(CacheKey.perProfilePrefixes.isEmpty)
    }
}
