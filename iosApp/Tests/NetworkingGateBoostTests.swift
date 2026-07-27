//
//  NetworkingGateBoostTests.swift
//  PrairieTests
//
//  Extra Networking unit coverage toward the 90% scoped xccov gate
//  (models / persistence helpers / cache keys — not live HTTP clients).
//

import XCTest
import Foundation
@testable import Prairie

final class NetworkingGateBoostTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        HTTPClient.makeJSONDecoder()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    private func encodeSnake<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Library collections resolution

    func testLibraryCollectionsResolvedSectionsFlatAndGrouped() {
        let empty = LibraryCollectionsResponse(collections: [], sections: [])
        XCTAssertTrue(empty.resolvedSections.isEmpty)

        let flat = LibraryCollectionsResponse(
            collections: [
                LibraryCollection(id: "c1", name: "Favorites"),
                LibraryCollection(id: "c2", name: "Holiday"),
            ],
            sections: []
        )
        XCTAssertEqual(flat.resolvedSections.count, 1)
        XCTAssertEqual(flat.resolvedSections[0].id, "__flat__")
        XCTAssertEqual(flat.resolvedSections[0].collections.map(\.id), ["c1", "c2"])

        let grouped = LibraryCollectionsResponse(
            collections: [LibraryCollection(id: "c1", name: "Favorites")],
            sections: [
                LibraryCollectionSection(
                    id: "g1",
                    name: "Staff",
                    kind: .regular,
                    collections: [LibraryCollection(id: "c1", name: "Favorites")]
                ),
            ]
        )
        XCTAssertEqual(grouped.resolvedSections.map(\.id), ["g1"])
    }

    func testLibraryCollectionUnknownKindToleratesDecode() throws {
        let collection = try decode(LibraryCollection.self, """
        { "id": "c1", "title": "X", "kind": "brand_new_kind" }
        """)
        XCTAssertNil(collection.kind)
        XCTAssertEqual(collection.name, "X")
    }

    // MARK: - Sections / media-type helpers

    func testSectionsResponseStripsUnsupportedLibraryItems() throws {
        let response = try decode(SectionsResponse.self, """
        {
          "sections": [
            {
              "id": "s1",
              "section_type": "recently_added",
              "title": "Recent",
              "items": [
                { "content_id": "m1", "type": "movie", "title": "Film" },
                { "content_id": "x1", "type": "manga", "title": "Skip" }
              ]
            }
          ]
        }
        """)
        XCTAssertEqual(response.sections.first?.items.map(\.contentId), ["m1"])
        XCTAssertFalse(PrairieMediaType.isSupportedSectionItem("manga"))
        XCTAssertTrue(PrairieMediaType.isSupportedSectionItem("movie"))
        XCTAssertTrue(PrairieMediaType.isSeries("tv"))
        XCTAssertTrue(PrairieMediaType.isMovieLibrary("movie"))
        XCTAssertFalse(PrairieMediaType.isAudiobook("episode"))
    }

    func testItemDetailAudiobookFlagAndSeasonsEpisodesDefaults() throws {
        let audiobook = try decode(ItemDetail.self, """
        {
          "content_id": "ab1",
          "type": "audiobook",
          "title": "Book"
        }
        """)
        XCTAssertTrue(audiobook.isAudiobook)

        let seasons = try decode(SeasonsResponse.self, "{}")
        XCTAssertTrue(seasons.seasons.isEmpty)
        let episodes = try decode(EpisodesResponse.self, "{}")
        XCTAssertTrue(episodes.episodes.isEmpty)
    }

    // MARK: - WireFormat profile bodies

    func testUpdateAndCreateProfileBodiesEncodeSnakeCase() throws {
        var update = UpdateProfileBody()
        update.subtitleLanguage = "en"
        update.subtitleMode = "auto"
        update.showForcedSubtitles = true
        update.preferredMetadataLanguage = "es"
        let updateDict = try encodeSnake(update)
        XCTAssertEqual(updateDict["subtitle_language"] as? String, "en")
        XCTAssertEqual(updateDict["preferred_metadata_language"] as? String, "es")

        let create = CreateProfileRequestBody(
            name: "Kids",
            avatar: "🐯",
            pin: "1234",
            isChild: true
        )
        let createDict = try encodeSnake(create)
        XCTAssertEqual(createDict["name"] as? String, "Kids")
        XCTAssertEqual(createDict["is_child"] as? Bool, true)
        XCTAssertEqual(createDict["pin"] as? String, "1234")
    }

    // MARK: - Playback prefs + device login helpers

    func testSubtitleAndAudioPrefModeEnumsAndDeviceLoginStatus() throws {
        let sub = try decode(SubtitlePref.self, """
        {
          "series_id": "s1",
          "subtitle_mode": "always",
          "subtitle_language": "ja"
        }
        """)
        XCTAssertEqual(sub.subtitleModeEnum, .always)

        let audio = try decode(AudioPref.self, """
        { "series_id": "s1", "audio_track_index": 2, "audio_language": "en" }
        """)
        XCTAssertEqual(audio.audioTrackIndex, 2)

        XCTAssertEqual(DeviceLoginStatus(raw: "pending"), .pending)
        XCTAssertEqual(DeviceLoginStatus(raw: "approved"), .approved)
        XCTAssertEqual(DeviceLoginStatus(raw: "denied"), .denied)
        XCTAssertEqual(DeviceLoginStatus(raw: "expired"), .expired)
        XCTAssertEqual(DeviceLoginStatus(raw: "consumed"), .consumed)
        XCTAssertEqual(DeviceLoginStatus(raw: "weird"), .unknown)

        let capability = try decode(DeviceLoginCapabilityResponse.self, """
        { "remote_playback_handoff": true, "protocol_versions": [1, 2] }
        """)
        XCTAssertTrue(capability.remotePlaybackHandoff)
        XCTAssertEqual(capability.protocolVersions, [1, 2])
    }

    // MARK: - Cache keys + AI tolerant edges

    @MainActor
    func testAdditionalCacheKeyBuilders() {
        XCTAssertEqual(CacheKey.itemDetail("x"), "item:x")
        XCTAssertEqual(CacheKey.itemSeasons("x"), "item:x:seasons")
        XCTAssertEqual(CacheKey.itemEpisodes(seriesId: "x", seasonNumber: 2), "item:x:season:2:episodes")
        XCTAssertEqual(CacheKey.itemWatchDetail("w"), "item:w:watchDetail")
        XCTAssertEqual(CacheKey.itemUserState("w"), "item:w:userState")
        XCTAssertEqual(CacheKey.librarySections(3), "library:3:sections")
        XCTAssertEqual(CacheKey.collectionItems("c1"), "collection:c1:items")
        XCTAssertEqual(CacheKey.similar("m1"), "item:m1:similar")
        XCTAssertEqual(CacheKey.adminStats, "admin:stats")
        XCTAssertEqual(CacheKey.collections, "collections:list")
        XCTAssertEqual(CacheKey.profiles, "profiles:list")
        XCTAssertEqual(CacheKey.favorites, "personal:favorites")
        XCTAssertEqual(CacheKey.userLibraries, "user:libraries")
        XCTAssertFalse(CacheKey.perProfilePrefixes.isEmpty)
    }

    func testAIJobStatusAndMetadataOnViewTolerance() throws {
        XCTAssertTrue(AIJobStatus.completed.isTerminal)
        XCTAssertTrue(AIJobStatus.failed.isTerminal)
        XCTAssertTrue(AIJobStatus.cancelled.isTerminal)
        XCTAssertFalse(AIJobStatus.pending.isTerminal)
        XCTAssertFalse(AIJobStatus.running.isTerminal)

        let unknownStatus = try decode(AIJobStatus.self, "\"brand_new\"")
        XCTAssertEqual(unknownStatus, .pending)

        let status = try decode(MetadataAIStatus.self, """
        { "enabled": true, "on_view": "mystery" }
        """)
        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.onView, .off)

        let body = TranslateDescriptionBody(targetLanguage: "fr")
        let encoded = try encodeSnake(body)
        XCTAssertEqual(encoded["target_language"] as? String, "fr")
    }

    func testBrowseItemAudiobookAndLibraryHelpers() throws {
        let item = try decode(BrowseItem.self, """
        { "content_id": "a1", "type": "audiobook", "title": "Listen" }
        """)
        XCTAssertTrue(item.isAudiobook)

        let library = try decode(Library.self, """
        { "id": 2, "name": "Shows", "type": "tv" }
        """)
        XCTAssertTrue(library.isSeriesLibrary)
        XCTAssertFalse(library.isMovieLibrary)
        XCTAssertTrue(library.isSupportedLibrary)
    }
}
