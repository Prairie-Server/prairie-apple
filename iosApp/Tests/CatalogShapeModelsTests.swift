import Foundation
import XCTest
@testable import Prairie

/// The presentation shapes the API v2 catalog reads fill in: catalog pages as
/// card grids, section/browse row conversions, server-relative artwork, and
/// the small request and response bodies around collections and seasons.
final class CatalogShapeModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String, server: String? = nil) throws -> T {
        try HTTPClient.makeJSONDecoder(artworkServerURL: server.flatMap(URL.init(string:)))
            .decode(T.self, from: Data(json.utf8))
    }

    private let browseJSON = #"""
    { "content_id": "movie:1", "type": "movie", "title": "Heat", "year": 1995, "genres": ["Crime"],
      "status": "available", "rating_imdb": 8.3, "rating_tmdb": 7.9, "rating_rt_critic": 88,
      "rating_rt_audience": 94, "content_rating": "R", "runtime": 170, "original_language": "en",
      "studios": ["Warner"], "networks": [], "show_status": "released", "overview": "Cops and robbers.",
      "poster_url": "/api/v2/images/poster/1?sig=a%2Fb", "poster_thumbhash": "p",
      "backdrop_url": "https://cdn.example/backdrop.jpg", "backdrop_thumbhash": "b",
      "user_state": { "played": true, "is_favorite": false, "in_watchlist": true },
      "overlay_summary": { "resolution": "2160p", "hdr": "HDR10" } }
    """#

    func testCatalogPageBecomesACardGrid() throws {
        let page = try decode(APIv2CatalogPage.self, """
        { "items": [\(browseJSON)], "page": { "has_more": true, "next_cursor": "c2" },
          "total": 41, "total_exact": false, "window_cursor": "w" }
        """, server: "https://media.example")
        let response = CatalogResponse(catalogPage: page)
        XCTAssertEqual(response.items.map(\.contentId), ["movie:1"])
        XCTAssertEqual(response.total, 41)
        XCTAssertEqual(response.totalExact, false)
        XCTAssertEqual(response.hasMore, true)

        let empty = try decode(CatalogResponse.self, "{}")
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertNil(empty.total)
    }

    func testServerRelativeArtworkResolvesAgainstTheDecodingServer() throws {
        let resolved = try decode(BrowseItem.self, browseJSON, server: "https://media.example/prairie/?x=1")
        XCTAssertEqual(resolved.posterUrl, "https://media.example/api/v2/images/poster/1?sig=a%2Fb")
        XCTAssertEqual(resolved.backdropUrl, "https://cdn.example/backdrop.jpg")

        let unresolved = try decode(BrowseItem.self, browseJSON)
        XCTAssertEqual(unresolved.posterUrl, "/api/v2/images/poster/1?sig=a%2Fb")

        let protocolRelative = browseJSON.replacingOccurrences(
            of: "/api/v2/images/poster/1?sig=a%2Fb", with: "//evil.example/p.jpg")
        XCTAssertEqual(try decode(BrowseItem.self, protocolRelative, server: "https://media.example").posterUrl,
                       "//evil.example/p.jpg")
    }

    func testSectionAndBrowseRowsConvertBothWays() throws {
        let browse = try decode(BrowseItem.self, browseJSON, server: "https://media.example")
        let section = SectionItem(browseItem: browse, positionSeconds: 60, durationSeconds: 600)
        XCTAssertEqual(section.contentId, "movie:1")
        XCTAssertEqual(section.title, "Heat")
        XCTAssertEqual(section.year, 1995)
        XCTAssertEqual(section.genres, ["Crime"])
        XCTAssertEqual(section.ratingRtAudience, 94)
        XCTAssertEqual(section.runtime, 170)
        XCTAssertEqual(section.positionSeconds, 60)
        XCTAssertEqual(section.durationSeconds, 600)
        XCTAssertEqual(section.posterUrl, "https://media.example/api/v2/images/poster/1?sig=a%2Fb")
        XCTAssertEqual(section.userState?.inWatchlist, true)
        XCTAssertEqual(section.overlaySummary?.hdr, "HDR10")
        XCTAssertNil(section.seriesId)
        XCTAssertNil(section.logoUrl)
        XCTAssertFalse(section.isAudiobook)

        let back = try XCTUnwrap(BrowseItem(sectionItem: section))
        XCTAssertEqual(back.contentId, browse.contentId)
        XCTAssertEqual(back.posterUrl, section.posterUrl)
        XCTAssertEqual(back.userState?.played, true)

        let plain = SectionItem(browseItem: browse)
        XCTAssertNil(plain.positionSeconds)
    }

    func testSeasonNamesSelectionIndexesAndResponseWrappers() throws {
        let seasons = try decode([Season].self, """
        [ { "content_id": "s0", "season_number": 0, "title": "Specials", "episode_count": 2 },
          { "content_id": "s00", "season_number": 0, "episode_count": 2 },
          { "content_id": "sx", "season_number": 9, "is_specials": true, "title": "Extras", "episode_count": 1 },
          { "content_id": "s3", "season_number": 3, "title": "Third", "episode_count": 8 } ]
        """)
        XCTAssertEqual(seasons.map(\.downloadDisplayName), ["Specials", "Specials", "Extras", "Season 3"])
        XCTAssertEqual(SeasonsResponse(seasons: seasons).seasons.count, 4)
        XCTAssertTrue(EpisodesResponse(episodes: []).episodes.isEmpty)

        let tracks = try decode([SubtitleTrack].self, """
        [ { "index": 4, "language": "en" },
          { "language": "fr", "external": true, "external_path": "/subs/fr.srt" },
          { "language": "de" } ]
        """)
        XCTAssertEqual(tracks.map(\.selectionIndex), [4, nil, 0])
    }

    func testCollectionAndUserBodies() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        func object<T: Encodable>(_ value: T) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
        }
        let create = try object(CreateCollectionRequest(name: "Faves", collectionType: "manual"))
        XCTAssertEqual(create["name"] as? String, "Faves")
        XCTAssertEqual(create["collection_type"] as? String, "manual")
        XCTAssertEqual(try object(CreateCollectionGroupRequest(name: "Group"))["name"] as? String, "Group")
        XCTAssertEqual(try object(UpdateCollectionGroupRequest(name: "Renamed"))["name"] as? String, "Renamed")

        let user = try decode(UserInfo.self, #"{ "id": "u1", "username": "ada", "is_admin": true }"#)
        XCTAssertEqual(user.username, "ada")
        XCTAssertEqual(user.isAdmin, true)
    }
}
