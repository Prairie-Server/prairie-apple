import Foundation
import XCTest
@testable import Prairie

/// Catalog query parameters and bodies, catalog/collection page decoding,
/// progress sync batches and their outcomes, mutation delivery, and the
/// update-requirement classification the v2 client raises.
final class APIv2CatalogQueryAndSyncTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func problem(status: Int, identifier: String) throws -> APIv2Problem {
        try decode(APIv2Problem.self, """
        { "type": "https://prairieserver.org/docs/api/v2/problems/\(identifier)", "title": "t",
          "status": \(status), "detail": "d" }
        """)
    }

    // MARK: - Catalog query

    func testCatalogQueryParameters() throws {
        var query = APIv2CatalogQuery()
        query.scope = "library"
        query.sectionId = "s1"
        query.collectionId = "c1"
        query.personId = "p1"
        query.libraryId = "3"
        query.q = "heat"
        query.type = "movie"
        query.namePrefix = "H"
        query.group = "year"
        query.imageSize = "medium"
        query.sort = "title"
        query.order = "desc"
        query.limit = 25
        query.queryLimit = 500
        query.skipTotal = true
        query.groups = [APIv2CatalogGroup(match: "any", rules: [
            APIv2CatalogRule(field: "genre", op: "in", value: .strings(["Drama", "Crime"])),
            APIv2CatalogRule(field: "year", op: "gte", value: .number(1990)),
            APIv2CatalogRule(field: "rating", op: "between", value: .numbers([6, 9])),
            APIv2CatalogRule(field: "played", op: "eq", value: .bool(false)),
            APIv2CatalogRule(field: "studio", op: "eq", value: .string("A24")),
        ])]

        let parameters = try query.getParameters()
        XCTAssertEqual(parameters["source"], "query")
        XCTAssertEqual(parameters["limit"], "25")
        XCTAssertEqual(parameters["match"], "all")
        XCTAssertEqual(parameters["scope"], "library")
        XCTAssertEqual(parameters["section_id"], "s1")
        XCTAssertEqual(parameters["collection_id"], "c1")
        XCTAssertEqual(parameters["person_id"], "p1")
        XCTAssertEqual(parameters["library_id"], "3")
        XCTAssertEqual(parameters["q"], "heat")
        XCTAssertEqual(parameters["type"], "movie")
        XCTAssertEqual(parameters["name_prefix"], "H")
        XCTAssertEqual(parameters["group"], "year")
        XCTAssertEqual(parameters["image_size"], "medium")
        XCTAssertEqual(parameters["sort"], "-title")
        XCTAssertEqual(parameters["query_limit"], "500")
        XCTAssertEqual(parameters["skip_total"], "true")
        let groups = try XCTUnwrap(parameters["groups"])
        XCTAssertTrue(groups.contains(#""value":["Drama","Crime"]"#), groups)
        XCTAssertTrue(groups.contains(#""value":1990"#), groups)
        XCTAssertTrue(groups.contains(#""value":false"#), groups)
        XCTAssertTrue(groups.contains(#""value":"A24""#), groups)
        XCTAssertEqual(query.preferredOperation, .get)

        var ascending = APIv2CatalogQuery()
        ascending.sort = "year"
        let plain = try ascending.getParameters()
        XCTAssertEqual(plain["sort"], "year")
        XCTAssertNil(plain["groups"])
        XCTAssertNil(plain["skip_total"])
        XCTAssertNil(plain["query_limit"])

        var huge = APIv2CatalogQuery()
        huge.groups = [APIv2CatalogGroup(match: "any", rules: [
            APIv2CatalogRule(field: "title", op: "in",
                             value: .strings((0..<3000).map { "title-number-\($0)" })),
        ])]
        XCTAssertEqual(huge.preferredOperation, .query)

        let invalid: [(inout APIv2CatalogQuery) -> Void] = [
            { $0.limit = 0 },
            { $0.limit = 101 },
            { $0.queryLimit = -1 },
            { $0.sort = "-title" },
            { $0.sort = "title,year" },
            { $0.order = "sideways" },
        ]
        for mutate in invalid {
            var bad = APIv2CatalogQuery()
            mutate(&bad)
            XCTAssertThrowsError(try bad.getParameters())
            XCTAssertEqual(bad.preferredOperation, .get, "an invalid query falls back to GET sizing")
        }
    }

    func testCatalogQueryFactoriesAndBody() throws {
        let history = APIv2CatalogQuery.history(limit: 10)
        XCTAssertEqual(history.source, "history")
        XCTAssertEqual(history.limit, 10)

        let credits = APIv2CatalogQuery.personCredits(personId: "person:1", type: "movie", limit: 20)
        XCTAssertEqual(try credits.getParameters()["sort"], "-year")
        XCTAssertEqual(credits.personId, "person:1")
        XCTAssertEqual(credits.source, "person")

        let collection = APIv2CatalogQuery.collectionItems(kind: .userCollections, collectionId: "c9", limit: 30)
        XCTAssertEqual(collection.source, "user_collection")
        XCTAssertEqual(collection.collectionId, "c9")

        let search = APIv2CatalogQuery.search("heat", type: nil, limit: 5)
        XCTAssertEqual(search.q, "heat")
        XCTAssertNil(search.type)

        let body = try object(APIv2CatalogQueryBody(query: search, cursor: "next"))
        XCTAssertEqual(body["q"] as? String, "heat")
        XCTAssertEqual(body["cursor"] as? String, "next")
        XCTAssertEqual(body["limit"] as? Int, 5)
        XCTAssertEqual(body["skipTotal"] as? Bool, false)
        XCTAssertNil(try object(APIv2CatalogQueryBody(query: search, cursor: nil))["cursor"])
        XCTAssertEqual(APIv2CatalogOperation.query.rawValue, "query")
    }

    func testCatalogRestartClassification() throws {
        XCTAssertTrue(APIv2Error.isCatalogRestart(APIv2Error.invalidCatalogContinuation))
        XCTAssertTrue(APIv2Error.isCatalogRestart(APIv2Error.problem(try problem(status: 400, identifier: "invalid_cursor"))))
        XCTAssertFalse(APIv2Error.isCatalogRestart(APIv2Error.problem(try problem(status: 400, identifier: "bad_request"))))
        XCTAssertFalse(APIv2Error.isCatalogRestart(URLError(.timedOut)))
    }

    func testCatalogPagesFiltersAndCollectionTabsDecode() throws {
        let page = try decode(APIv2CatalogPage.self, """
        { "items": [], "page": { "has_more": false }, "total": 0, "total_exact": true, "window_cursor": "w",
          "effective_sort": { "field": "title", "order": "asc" },
          "search_diagnostics": { "provider": "sqlite", "mode": "lexical", "semantic_used": false,
            "fallback_reason": "disabled", "index_pending_updates": 3, "result_window_limit": 500,
            "session_expires_at": "2026-01-01T00:00:00Z" } }
        """)
        XCTAssertEqual(page.effectiveSort, APIv2CatalogEffectiveSort(field: "title", order: "asc"))
        XCTAssertEqual(page.searchDiagnostics?.indexPendingUpdates, 3)
        XCTAssertEqual(page.windowCursor, "w")

        func capabilities(state: String, allowed: Bool) throws -> APIv2CatalogSearchCapabilities {
            try decode(APIv2CatalogSearchCapabilities.self, """
            { "revision": "1", "state": "\(state)", "allowed": \(allowed), "provider": "sqlite",
              "result_window_limit": 500, "session_ttl_seconds": 60, "max_sessions_per_account": 4,
              "people_media_scope": true, "person_prefetch": false }
            """)
        }
        XCTAssertTrue(try capabilities(state: "available", allowed: true).isAvailable)
        XCTAssertFalse(try capabilities(state: "available", allowed: false).isAvailable)
        XCTAssertFalse(try capabilities(state: "disabled", allowed: true).isAvailable)

        let filters = try decode(APIv2CatalogFilters.self, """
        { "genres": ["Drama"], "studios": [], "networks": [], "countries": ["US"], "content_ratings": ["PG"],
          "original_languages": ["en"], "authors": ["Ada"], "narrators": [], "series": ["Saga"],
          "technical": { "resolutions": ["2160p"], "audio_languages": ["en"], "subtitle_languages": ["fr"] } }
        """)
        XCTAssertEqual(filters.authors, ["Ada"])
        XCTAssertEqual(filters.technical?.resolutions, ["2160p"])

        let trailer = try decode(TrailerRefreshResponse.self, #"{ "status": "queued", "next_allowed_at": null }"#)
        XCTAssertEqual(trailer.status, "queued")

        let tab = try decode(APIv2LibraryCollectionTab.self, """
        { "library_id": "3",
          "collections": [{ "id": "c1", "library_id": "3", "library_ids": ["3"], "title": "Best",
            "collection_type": "curated", "poster_url": "https://cdn.example/c1.jpg", "poster_thumbhash": null,
            "item_count": 4, "sort_order": 1, "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z" }],
          "groups": [{ "id": "g1", "name": "Franchises", "kind": "manual", "sort_mode": "manual", "sort_order": 0,
            "collections": [{ "id": "c2", "title": "Saga", "poster_url": "https://cdn.example/c2.jpg",
                              "item_count": 3, "creator_profile_id": "p1" }] }],
          "ungrouped": { "sort_order": 2, "collections": [] } }
        """)
        XCTAssertEqual(tab.collections.first?.posterUrl, "https://cdn.example/c1.jpg")
        XCTAssertEqual(tab.groups.first?.collections.first?.creatorProfileId, "p1")
        XCTAssertEqual(tab.ungrouped?.sortOrder, 2)
    }

    // MARK: - Progress sync

    func testSyncProgressItemsAndBatches() throws {
        XCTAssertNil(SyncProgressItem(mediaItemId: " ", position: 1, duration: 2, forceOverwrite: false))
        XCTAssertNil(SyncProgressItem(mediaItemId: "m", position: -1, duration: 2, forceOverwrite: false))
        XCTAssertNil(SyncProgressItem(mediaItemId: "m", position: .nan, duration: 2, forceOverwrite: false))
        XCTAssertNil(SyncProgressItem(mediaItemId: "m", position: 1e300, duration: 2, forceOverwrite: false))
        XCTAssertEqual(SyncProgressItem.milliseconds(1.2346), 1235)

        let unknownDuration = try XCTUnwrap(SyncProgressItem(mediaItemId: "m", position: 1, duration: .infinity,
                                                             forceOverwrite: false))
        XCTAssertEqual(unknownDuration.durationMs, 0)
        let bare = try object(unknownDuration)
        XCTAssertEqual(bare["media_item_id"] as? String, "m")
        XCTAssertEqual(bare["position_ms"] as? Int, 1000)
        XCTAssertNil(bare["updated_at"])

        let stamped = try XCTUnwrap(SyncProgressItem(mediaItemId: "n", position: 2.5, duration: 60, forceOverwrite: true,
                                                     updatedAt: Date(timeIntervalSince1970: 1_700_000_000.25)))
        let body = try object(stamped)
        XCTAssertEqual(body["duration_ms"] as? Int, 60000)
        XCTAssertEqual(body["force_overwrite"] as? Bool, true)
        XCTAssertEqual(body["updated_at"] as? String, "2023-11-14T22:13:20.250Z")

        XCTAssertTrue(SyncProgressRequest(items: [unknownDuration, stamped]).isValidBatch)
        XCTAssertFalse(SyncProgressRequest(items: []).isValidBatch)
        XCTAssertFalse(SyncProgressRequest(items: [stamped, stamped]).isValidBatch)
        let tooMany = (0...SyncProgressRequest.maxItems).compactMap {
            SyncProgressItem(mediaItemId: "m\($0)", position: 1, duration: 2, forceOverwrite: false)
        }
        XCTAssertFalse(SyncProgressRequest(items: tooMany).isValidBatch)
    }

    func testProgressSyncOutcomes() throws {
        let result = try decode(APIv2ProgressSyncBatchResult.self, """
        { "items": [
            { "index": 0, "media_item_id": "m1", "status": "success" },
            { "index": 1, "media_item_id": "m2", "status": "failure",
              "failure": { "type": "not_found", "title": "Missing", "status": 404, "detail": "Gone" } },
            { "index": 2, "media_item_id": "m3", "status": "failure",
              "failure": { "type": "forbidden", "title": "No", "status": 403, "detail": "Nope" } } ],
          "summary": { "total": 3, "succeeded": 1, "failed": 2 } }
        """)
        XCTAssertEqual(result.summary, APIv2BulkSummary(total: 3, succeeded: 1, failed: 2))
        XCTAssertTrue(result.items[0].succeeded)
        XCTAssertFalse(result.items[1].succeeded)

        let mixed = ProgressSyncOutcome.answered(result.items)
        XCTAssertFalse(mixed.allSucceeded)
        XCTAssertEqual(mixed.failureSummary, "2 of 3 items failed (403 forbidden, 404 not_found)")

        let clean = ProgressSyncOutcome.answered([result.items[0]])
        XCTAssertTrue(clean.allSucceeded)
        XCTAssertNil(clean.failureSummary)

        let error = ProgressSyncError.invalidBatch
        let cases: [(ProgressSyncOutcome, String)] = [
            (.notSent(error), "not sent: "), (.deferred(error), "deferred: "),
            (.rejected(error), "rejected: "), (.uncertain(error), "outcome unknown, not resent: "),
        ]
        for (outcome, prefix) in cases {
            XCTAssertFalse(outcome.allSucceeded)
            XCTAssertTrue(outcome.failureSummary?.hasPrefix(prefix) == true, outcome.failureSummary ?? "nil")
        }
        XCTAssertFalse((ProgressSyncError.invalidBatch.errorDescription ?? "").isEmpty)
        XCTAssertFalse((ProgressSyncError.incompleteResult.errorDescription ?? "").isEmpty)
        XCTAssertFalse((ProgressReadError.incompleteRead.errorDescription ?? "").isEmpty)
    }

    // MARK: - Mutation delivery and update requirements

    func testMutationDeliveryClassification() {
        XCTAssertEqual(MutationDelivery(HTTPError.http(statusCode: 409, body: nil)), .definite)
        XCTAssertEqual(MutationDelivery(HTTPError.serverUrlNotConfigured), .definite)
        XCTAssertEqual(MutationDelivery(HTTPError.requestIdentityChanged), .ownerChanged)
        XCTAssertEqual(MutationDelivery(URLError(.networkConnectionLost)), .unconfirmed)
        XCTAssertEqual(MutationDelivery(CancellationError()), .unconfirmed)
        XCTAssertEqual(MutationDelivery.ownerChanged.rawValue, "owner_changed")
    }

    func testUpdateRequirementClassification() throws {
        XCTAssertEqual(UpdateRequirement(UpdateRequirement.app), .app)
        XCTAssertEqual(UpdateRequirement(APIv2Error.serverUpdateRequired), .server)
        XCTAssertEqual(UpdateRequirement(APIv2Error.problem(try problem(status: 410, identifier: "client_upgrade_required"))), .app)
        XCTAssertNil(UpdateRequirement(APIv2Error.problem(try problem(status: 400, identifier: "client_upgrade_required"))))
        XCTAssertNil(UpdateRequirement(APIv2Error.problem(try problem(status: 410, identifier: "gone"))))
        XCTAssertEqual(UpdateRequirement(HTTPError.http(statusCode: 410, body: #"{"error":"client_upgrade_required"}"#)), .app)
        let problemBody = #"{"type":"https://prairieserver.org/docs/api/v2/problems/client_upgrade_required","title":"t","status":410,"detail":"d"}"#
        XCTAssertEqual(UpdateRequirement(HTTPError.http(statusCode: 410, body: problemBody)), .app)
        XCTAssertNil(UpdateRequirement(HTTPError.http(statusCode: 410, body: #"{"error":"gone"}"#)))
        XCTAssertNil(UpdateRequirement(HTTPError.http(statusCode: 410, body: nil)))
        XCTAssertNil(UpdateRequirement(HTTPError.http(statusCode: 500, body: nil)))
        XCTAssertNil(UpdateRequirement(URLError(.timedOut)))

        XCTAssertEqual(UpdateRequirement(v2StatusCode: 404, body: "404 page not found"), .server)
        XCTAssertEqual(UpdateRequirement(v2StatusCode: 404, body: "404 page not found\n"), .server)
        XCTAssertNil(UpdateRequirement(v2StatusCode: 404, body: " 404 page not found"))
        XCTAssertNil(UpdateRequirement(v2StatusCode: 404, body: nil))
        XCTAssertEqual(UpdateRequirement(v2StatusCode: 410, body: #"{"error":"client_upgrade_required"}"#), .app)
        XCTAssertNil(UpdateRequirement(v2StatusCode: 500, body: "x"))

        XCTAssertEqual(UpdateRequirement.server.message, UpdateRequirement.serverMessage)
        XCTAssertEqual(UpdateRequirement.app.errorDescription, UpdateRequirement.appMessage)
    }
}
