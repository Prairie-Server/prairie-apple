//
//  NetworkingModelsCoverageTests.swift
//  PrairieTests
//
//  Broader decoding + helper coverage for Models.swift pure-logic surface.
//

import XCTest
import Foundation
@testable import Prairie

final class NetworkingModelsCoverageTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        HTTPClient.makeJSONDecoder()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    func testPrairieMediaTypeHelpers() {
        XCTAssertTrue(PrairieMediaType.isAudiobook(" Book "))
        XCTAssertTrue(PrairieMediaType.isSeries("TVShows"))
        XCTAssertTrue(PrairieMediaType.isMovieLibrary("movies"))
        XCTAssertTrue(PrairieMediaType.isDirectlyPlayable("episode"))
        XCTAssertTrue(PrairieMediaType.isDirectlyPlayable("movie"))
        XCTAssertFalse(PrairieMediaType.isDirectlyPlayable("series"))
        XCTAssertTrue(PrairieMediaType.isAudiobookLibrary("audiobooks"))
        XCTAssertFalse(PrairieMediaType.isAudiobookLibrary("book"))
        XCTAssertTrue(PrairieMediaType.isMixedLibrary("mixed"))
        XCTAssertTrue(PrairieMediaType.isSupportedLibrary("mixed"))
        XCTAssertTrue(PrairieMediaType.isSupportedSectionItem("episodes"))
        XCTAssertFalse(PrairieMediaType.isSupportedSectionItem("manga"))
    }

    func testBrowseItemAndCatalogFilters() throws {
        let item = try decode(BrowseItem.self, """
        {
          "content_id": "m1",
          "type": "movie",
          "title": "Film",
          "year": 2024,
          "genres": ["Action"],
          "rating_imdb": 7.5,
          "overlay_summary": {
            "resolution": "2160p",
            "hdr": "Dolby Vision",
            "multi_audio": true
          },
          "user_state": {
            "played": true,
            "is_favorite": false,
            "in_watchlist": true
          }
        }
        """)
        XCTAssertEqual(item.id, "m1")
        XCTAssertFalse(item.isAudiobook)
        XCTAssertEqual(item.overlaySummary?.resolution, "2160p")
        XCTAssertEqual(item.userState?.inWatchlist, true)

        let filters = try decode(CatalogFilters.self, """
        {
          "genres": ["Drama"],
          "studios": [],
          "networks": [],
          "countries": ["US"],
          "content_ratings": ["PG"],
          "authors": ["Ada"]
        }
        """)
        XCTAssertEqual(filters.authors, ["Ada"])
    }

    func testCatalogResponseDefaultsEmptyItems() throws {
        let response = try decode(CatalogResponse.self, """
        { "total": 0 }
        """)
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertEqual(response.total, 0)
    }

    func testResolvedSectionFeaturedFlag() throws {
        let section = try decode(ResolvedSection.self, """
        {
          "id": "s1",
          "section_type": "continue_watching",
          "title": "Continue",
          "featured": true,
          "items": [
            { "content_id": "m1", "type": "movie", "title": "A" }
          ]
        }
        """)
        XCTAssertTrue(section.isFeatured)
        XCTAssertEqual(section.items.first?.contentId, "m1")
    }

    func testSeasonSortAndEditionLabel() throws {
        let seasons = try decode([Season].self, """
        [
          { "content_id": "s2", "season_number": 2, "title": "Two", "episode_count": 10 },
          { "content_id": "s0", "season_number": 0, "title": "Specials", "episode_count": 1 },
          { "content_id": "s1", "season_number": 1, "title": "One", "episode_count": 8 }
        ]
        """)
        XCTAssertEqual(seasons.sortedForDisplay().map(\.seasonNumber), [1, 2, 0])

        let file = FileVersion(
            fileId: 9,
            fileName: "a.mkv",
            resolution: nil,
            codecVideo: nil,
            codecAudio: nil,
            hdr: nil,
            container: nil,
            fileSize: nil,
            duration: nil,
            bitrate: nil,
            videoTracks: nil,
            audioTracks: nil,
            subtitleTracks: nil,
            chapters: nil,
            edition: "  Director's Cut  "
        )
        XCTAssertEqual(file.id, 9)
        XCTAssertEqual(file.editionDisplayLabel, "Director's Cut")
    }

    func testWatchDetailTolerantDecode() throws {
        let detail = try decode(WatchDetail.self, """
        {
          "content_id": "e1",
          "type": "episode",
          "title": "Pilot"
        }
        """)
        XCTAssertEqual(detail.contentId, "e1")
        XCTAssertEqual(detail.type, "episode")
        XCTAssertTrue(detail.versions.isEmpty)
    }

    func testLibraryCollectionKindCatalogSource() {
        XCTAssertEqual(LibraryCollectionKind.regular.catalogSource, "library_collection")
        XCTAssertEqual(LibraryCollectionKind.userCollections.catalogSource, "user_collection")
    }

    func testPersonAndCreditIdentities() throws {
        let person = try decode(Person.self, """
        { "id": 1, "name": "Ada" }
        """)
        XCTAssertEqual(person.id, 1)

        let cast = try decode(CastMember.self, """
        { "name": "Ada", "character": "Lead" }
        """)
        XCTAssertTrue(cast.id.contains("Ada"))

        let crew = try decode(CrewMember.self, """
        { "name": "Ada", "job": "Director" }
        """)
        XCTAssertTrue(crew.id.contains("Director"))
    }

    func testAudioSubtitleTrackIdentities() throws {
        let audio = try decode(AudioTrack.self, """
        { "index": 1, "language": "en", "codec": "aac", "channels": 2 }
        """)
        XCTAssertEqual(audio.id, 1)

        let sub = try decode(SubtitleTrack.self, """
        {
          "index": 2,
          "language": "es",
          "codec": "subrip",
          "file_name": "/subs/es.srt"
        }
        """)
        XCTAssertEqual(sub.id, "2|/subs/es.srt")
    }

    func testLibraryHelpers() throws {
        let library = try decode(Library.self, """
        { "id": 1, "name": "Movies", "type": "movies" }
        """)
        XCTAssertTrue(library.isMovieLibrary)
        XCTAssertTrue(library.isSupportedLibrary)
        XCTAssertFalse(library.isSeriesLibrary)
    }

    func testFileVersionDecodeAndAdminStats() throws {
        let version = try decode(FileVersion.self, """
        {
          "file_id": 3,
          "file_name": "movie.mkv",
          "resolution": "1080p",
          "edition_raw": "Extended",
          "audio_tracks": [
            { "index": 0, "language": "en", "codec": "aac", "channels": 2 }
          ],
          "subtitle_tracks": [
            { "index": 1, "language": "en", "codec": "subrip" }
          ],
          "trickplay": {
            "interval_seconds": 10,
            "width": 320,
            "height": 180,
            "tile_columns": 10,
            "tile_rows": 10,
            "thumbnail_count": 12,
            "sheets": [
              { "index": 0, "url": "https://cdn.example.com/0.webp" }
            ]
          }
        }
        """)
        XCTAssertEqual(version.fileId, 3)
        XCTAssertEqual(version.editionDisplayLabel, "Extended")
        XCTAssertEqual(version.audioTracks?.count, 1)
        XCTAssertEqual(version.subtitleTracks?.first?.language, "en")
        XCTAssertEqual(version.trickplay?.thumbnailCount, 12)
        XCTAssertEqual(version.trickplay?.sheets.first?.url, "https://cdn.example.com/0.webp")

        let stats = try decode(AdminStats.self, """
        {
          "total_items": 10,
          "total_files": 20,
          "total_users": 2,
          "active_streams": 1
        }
        """)
        XCTAssertEqual(stats.totalItems, 10)
        XCTAssertEqual(stats.activeStreams, 1)
    }

    func testCollectionItemsAndLibrariesObjectShape() throws {
        let items = try decode(CollectionItemsResponse.self, "{}")
        XCTAssertTrue(items.items.isEmpty)

        let libraries = try decode(LibrariesResponse.self, """
        {
          "libraries": [
            { "id": 1, "name": "Movies", "type": "movies" },
            { "id": 2, "name": "Music", "type": "music" }
          ]
        }
        """)
        XCTAssertEqual(libraries.libraries.map(\.id), [1])
    }

    func testEpisodeListItemAndTimeRange() throws {
        let episode = try decode(EpisodeListItem.self, """
        {
          "content_id": "e1",
          "season_number": 1,
          "episode_number": 2,
          "title": "Pilot",
          "files": [
            { "file_id": 9, "resolution": "1080p", "hdr": true }
          ]
        }
        """)
        XCTAssertEqual(episode.id, "e1")
        XCTAssertEqual(episode.files?.first?.fileId, 9)

        let range = try decode(TimeRange.self, """
        { "start": 10.5, "end": 20.0 }
        """)
        XCTAssertEqual(range.start, 10.5)
        XCTAssertEqual(range.end, 20.0)
    }
}
