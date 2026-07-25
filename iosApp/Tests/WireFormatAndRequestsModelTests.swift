//
//  WireFormatAndRequestsModelTests.swift
//  PrairieTests
//

import XCTest
import Foundation
@testable import Prairie

final class WireFormatAndRequestsModelTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        HTTPClient.makeJSONDecoder()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - WireFormat / profiles

    func testProfileAsUserProfile() throws {
        let profile = try decode(Profile.self, """
        {
          "id": "p1",
          "name": "Kids",
          "avatar": "🐯",
          "has_pin": true,
          "is_child": true,
          "is_primary": false,
          "subtitle_language": "en",
          "subtitle_mode": "auto",
          "show_forced_subtitles": true,
          "preferred_metadata_language": "es"
        }
        """)
        let user = profile.asUserProfile
        XCTAssertEqual(user.id, "p1")
        XCTAssertTrue(user.hasPin)
        XCTAssertTrue(user.isChild)
        XCTAssertEqual(user.preferredMetadataLanguage, "es")
    }

    func testProfilesResponseAndPinVerify() throws {
        let profiles = try decode(ProfilesResponse.self, """
        { "profiles": [ { "id": "a", "name": "A" } ] }
        """)
        XCTAssertEqual(profiles.profiles.count, 1)

        let pin = try decode(VerifyPinResponse.self, """
        { "valid": true, "profile_token": "tok", "expires_at": "soon" }
        """)
        XCTAssertTrue(pin.valid)
        XCTAssertEqual(pin.profileToken, "tok")
    }

    func testDiscoverAndSimilarWire() throws {
        let discover = try decode(DiscoverResponse.self, """
        {
          "rows": [
            {
              "type": "because_you_watched",
              "label": "Because",
              "items": [
                { "content_id": "1", "type": "movie", "title": "One" }
              ]
            }
          ]
        }
        """)
        XCTAssertEqual(discover.rows.count, 1)
        XCTAssertEqual(discover.rows[0].items.first?.contentId, "1")

        let empty = try decode(DiscoverResponse.self, "{}")
        XCTAssertTrue(empty.rows.isEmpty)

        let similar = try decode(ScoredItemsResponse.self, """
        { "items": [ { "media_item_id": "m1", "score": 0.9, "reason": "cast" } ] }
        """)
        XCTAssertEqual(similar.items.first?.id, "m1")
        XCTAssertEqual(similar.items.first?.score, 0.9)
    }

    func testLibraryCollectionsWireArrayShape() throws {
        // LibraryCollection maps JSON `title` → `name`.
        let wire = try decode(LibraryCollectionsWireResponse.self, """
        [
          {
            "id": "c1",
            "title": "Favorites",
            "item_count": 3,
            "poster_url": "https://ex/p.png"
          },
          { "broken": true }
        ]
        """)
        XCTAssertEqual(wire.collections.count, 1)
        XCTAssertEqual(wire.collections[0].id, "c1")
        XCTAssertEqual(wire.collections[0].name, "Favorites")
        XCTAssertTrue(wire.sections.isEmpty)
    }

    func testLibraryCollectionsWireGroupedShape() throws {
        let wire = try decode(LibraryCollectionsWireResponse.self, """
        {
          "groups": [
            {
              "id": "g1",
              "name": "Studios",
              "kind": "user_collections",
              "sort_order": 2,
              "collections": [
                { "id": "pixar", "title": "Pixar", "item_count": 10 }
              ]
            }
          ],
          "ungrouped": {
            "sort_order": 1,
            "collections": [
              { "id": "misc", "title": "Misc", "item_count": 1 }
            ]
          }
        }
        """)
        XCTAssertEqual(wire.collections.count, 2)
        XCTAssertEqual(wire.sections.count, 2)
        // Ungrouped sort_order 1 comes before group sort_order 2.
        XCTAssertEqual(wire.sections[0].id, "__ungrouped__")
        XCTAssertEqual(wire.sections[1].id, "g1")
        XCTAssertEqual(wire.sections[1].kind, .userCollections)
    }

    func testLibraryCollectionsFlatObjectShape() throws {
        let wire = try decode(LibraryCollectionsWireResponse.self, """
        {
          "collections": [
            { "id": "c1", "title": "One", "item_count": 1 }
          ]
        }
        """)
        XCTAssertEqual(wire.collections.map(\.id), ["c1"])
        XCTAssertTrue(wire.sections.isEmpty)
    }

    // MARK: - Requests models

    func testRequestEnumsTolerateUnknown() throws {
        XCTAssertEqual(try decode(RequestMediaType.self, "\"movie\""), .movie)
        XCTAssertEqual(try decode(RequestMediaType.self, "\"future\""), .unknown)
        XCTAssertEqual(RequestMediaType.series.displayName, "Series")
        XCTAssertEqual(try decode(RequestStatus.self, "\"queued\""), .queued)
        XCTAssertEqual(try decode(RequestStatus.self, "\"zzz\""), .unknown)
        XCTAssertEqual(try decode(RequestOutcome.self, "\"declined\""), .declined)
        XCTAssertEqual(try decode(RequestAvailability.self, "\"available\""), .available)
    }

    func testRequestMediaPageAndDetail() throws {
        let page = try decode(RequestMediaPage.self, """
        {
          "page": 1,
          "total_pages": 2,
          "total_results": 3,
          "results": [
            {
              "media_type": "movie",
              "tmdb_id": 42,
              "title": "Film",
              "year": 2024,
              "availability": "missing",
              "request": { "requestable": true, "reason": null, "request_id": null }
            }
          ]
        }
        """)
        XCTAssertEqual(page.results.first?.id, "movie:42")
        XCTAssertTrue(page.results.first?.request.requestable ?? false)

        let detail = try decode(RequestMediaDetail.self, """
        {
          "media_type": "series",
          "tmdb_id": 9,
          "title": "Show",
          "availability": "available",
          "library_content_id": "c9",
          "request": {
            "status": "completed",
            "requestable": false,
            "reason": "already_requested",
            "request_id": "r1"
          }
        }
        """)
        XCTAssertEqual(detail.libraryContentId, "c9")
        XCTAssertEqual(detail.request.requestId, "r1")
    }

    func testMediaRequestAndDiscoverSections() throws {
        let requests = try decode(MediaRequestsResponse.self, """
        {
          "requests": [
            {
              "id": "r1",
              "media_type": "movie",
              "tmdb_id": 1,
              "title": "T",
              "status": "downloading",
              "outcome": "active",
              "targets": [
                { "quality": "1080p", "status": "downloading", "last_error": null }
              ],
              "created_at": "2026-01-01T00:00:00Z",
              "updated_at": "2026-01-01T00:00:00Z"
            }
          ]
        }
        """)
        XCTAssertEqual(requests.requests.first?.targets?.first?.quality, "1080p")

        let discover = try decode(RequestDiscoverResponse.self, """
        {
          "sections": [
            {
              "key": "trending_movies",
              "title": "Trending",
              "page": 1,
              "total_pages": 1,
              "total_results": 0,
              "results": []
            }
          ]
        }
        """)
        XCTAssertEqual(discover.sections.first?.id, "trending_movies")
    }

    func testFeatureStatusAndCreateInputEncode() throws {
        let status = try decode(RequestsFeatureStatus.self, """
        { "requests_enabled": true }
        """)
        XCTAssertTrue(status.requestsEnabled)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(CreateRequestInput(
            mediaType: .movie,
            tmdbId: 1,
            tvdbId: nil,
            imdbId: "tt1",
            title: "T",
            year: 2020,
            overview: nil,
            posterPath: nil,
            backdropPath: nil
        ))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["tmdb_id"] as? Int, 1)
        XCTAssertEqual(obj["imdb_id"] as? String, "tt1")
    }
}
