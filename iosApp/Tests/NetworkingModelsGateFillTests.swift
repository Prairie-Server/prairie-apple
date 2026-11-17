//
//  NetworkingModelsGateFillTests.swift
//  PrairieTests
//
//  Tiny decode/memberwise suite that closes the Models.swift gap the Networking
//  CI allowlist otherwise misses — without pulling in DetailVersionSelection /
//  PlaybackMediaFixture (hundreds of slower cases).
//

import XCTest
import Foundation
@testable import Prairie

final class NetworkingModelsGateFillTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        HTTPClient.makeJSONDecoder()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    private static let suppressionKey = "unrenderableOnboardingTour.v1"

    override func tearDown() {
        SharedDefaults.shared.removeObject(forKey: Self.suppressionKey)
        super.tearDown()
    }

    func testAudiobookDetailAndLeafUserDataDecode() throws {
        let detail = try decode(AudiobookDetail.self, """
        {
          "authors": [{ "name": "Ada" }],
          "narrators": [{ "name": "Nia" }],
          "publisher": "Prairie Press",
          "total_duration_seconds": 1800,
          "series": { "name": "Saga" },
          "other_narrations": [],
          "related": { "also_by_author": [], "similar": [] }
        }
        """)
        XCTAssertEqual(detail.authors.first?.name, "Ada")
        XCTAssertEqual(detail.narrators.first?.name, "Nia")
        XCTAssertEqual(detail.publisher, "Prairie Press")
        XCTAssertEqual(detail.totalDurationSeconds, 1800)
        XCTAssertEqual(detail.series?.name, "Saga")

        let userData = try decode(LeafItemUserData.self, """
        {
          "played": true,
          "is_in_progress": true,
          "position_seconds": 12.5,
          "duration_seconds": 100,
          "last_file_id": 7,
          "last_resolution": "1080p",
          "last_hdr": false,
          "last_codec_video": "hevc"
        }
        """)
        XCTAssertTrue(userData.played)
        XCTAssertEqual(userData.positionSeconds, 12.5)
        XCTAssertEqual(userData.lastFileId, 7)
    }

    func testPlaybackSessionMemberwiseAndLibraryHelpers() {
        let session = PlaybackSessionResponse(
            sessionId: "sess-fill",
            userId: 1,
            profileId: "p1",
            mediaFileId: 42,
            playMethod: "direct",
            position: 0,
            isPaused: false,
            streamUrl: "https://example.invalid/stream",
            audioTrackIndex: 0,
            durationSeconds: 2,
            subtitleUrls: nil,
            playbackInfo: nil
        )
        XCTAssertEqual(session.sessionId, "sess-fill")
        XCTAssertEqual(session.timelineOffsetSeconds, 0)

        let libraries = LibrariesResponse(libraries: [
            Library(id: 1, name: "Movies", type: "movies", sortOrder: nil, posterUrl: nil),
            Library(id: 2, name: "Music", type: "music", sortOrder: nil, posterUrl: nil),
            Library(id: 3, name: "Audiobooks", type: "audiobooks", sortOrder: nil, posterUrl: nil),
        ])
        XCTAssertEqual(libraries.libraries.map(\.id), [1, 3])
        XCTAssertTrue(libraries.libraries[1].isAudiobookLibrary)
    }

    func testFileVersionEditionAndSubtitleTrackIds() throws {
        let version = try decode(FileVersion.self, """
        {
          "file_id": 9,
          "file_name": "movie.mkv",
          "edition_raw": "  theatrical  ",
          "codec_video": "hevc",
          "codec_audio": "aac",
          "container": "mkv"
        }
        """)
        XCTAssertEqual(version.editionDisplayLabel, "theatrical")

        let withIndex = try decode(SubtitleTrack.self, """
        { "index": 2, "language": "en", "codec": "subrip" }
        """)
        XCTAssertEqual(withIndex.id, "2|")

        let withoutIndex = try decode(SubtitleTrack.self, """
        { "language": "en", "codec": "subrip", "file_name": "/subs/en.srt" }
        """)
        XCTAssertEqual(withoutIndex.id, "-1|/subs/en.srt")
    }

    // MARK: - Models.swift

    func testMediaItemUserStateEpisodesLeft() {
        XCTAssertEqual(MediaItemUserState(watchedCount: 1, unplayedCount: 3).episodesLeft, 3)
        XCTAssertNil(MediaItemUserState(played: true, watchedCount: 1, unplayedCount: 3).episodesLeft)
        XCTAssertNil(MediaItemUserState(watchedCount: 0, unplayedCount: 3).episodesLeft)
        XCTAssertNil(MediaItemUserState(watchedCount: 1, unplayedCount: 0).episodesLeft)
        XCTAssertNil(MediaItemUserState(watchedCount: 1, unplayedCount: nil).episodesLeft)
    }

    func testResolvedSectionDisplayTitleAndReplacingItems() {
        let section = ResolvedSection(
            id: "s1",
            sectionType: "shelf",
            title: "Server Title",
            featured: nil,
            itemLimit: 5,
            totalCount: 0,
            isCustom: false,
            customized: false,
            items: []
        )
        XCTAssertEqual(section.displayTitle(language: "en"), "Server Title")
        XCTAssertEqual(section.displayTitle(in: Locale(identifier: "en")), "Server Title")
        XCTAssertFalse(section.isFeatured)
        XCTAssertEqual(section.replacingItems([]).id, "s1")
    }

    func testLeafItemUserDataHasResumePoint() throws {
        let resumable = try decode(LeafItemUserData.self, #"""
        { "played": false, "position_seconds": 600, "duration_seconds": 7200 }
        """#)
        XCTAssertTrue(resumable.hasResumePoint)

        let atStart = try decode(LeafItemUserData.self, #"""
        { "played": true, "position_seconds": 5, "duration_seconds": 7200 }
        """#)
        XCTAssertFalse(atStart.hasResumePoint)

        let empty = try decode(LeafItemUserData.self, "{}")
        XCTAssertFalse(empty.played)
        XCTAssertFalse(empty.hasResumePoint)
    }

    func testLibraryCollectionDecodesWithoutKind() throws {
        let plain = try decode(LibraryCollection.self, #"{ "id": "c1", "title": "Plain" }"#)
        XCTAssertEqual(plain.name, "Plain")
        XCTAssertNil(plain.kind)

        let user = try decode(LibraryCollection.self, #"""
        { "id": "c2", "title": "Mine", "kind": "user_collections", "creator_profile_id": "p1" }
        """#)
        XCTAssertEqual(user.kind, .userCollections)
        XCTAssertEqual(user.creatorProfileId, "p1")

        let unknown = try decode(LibraryCollection.self, #"{ "id": "c3", "title": "X", "kind": "bogus" }"#)
        XCTAssertNil(unknown.kind)
    }

    // MARK: - PlaybackPrefsModels.swift

    func testUnsetLabelUsesManifestThenFallback() {
        let language = AppLanguage.shipped.first ?? "en"
        for key in [SettingKey.playbackAudioLanguage, SettingKey.catalogHideUnwatchedEpisodeImages] {
            let expected = SettingPresentationMetadata.definitions[key]?.unsetLabel ?? "fb"
            XCTAssertEqual(
                SettingPresentationMetadata.unsetLabel(for: key, fallback: "fb", language: language),
                expected
            )
        }
        XCTAssertEqual(
            SettingPresentationMetadata.unsetLabel(for: .playbackAudioLanguage, fallback: "fb", language: language),
            "No preference"
        )
    }

    func testLanguageIdentityMapsLegacyOriginalToSentinel() {
        XCTAssertEqual(
            PlaybackLanguageOption.languageIdentity("Original"),
            PlaybackPrefSentinel.originalLanguage
        )
    }

    func testTrackPrefBodyAppliedOverStored() throws {
        let audio = AudioPrefRequest(audioTrackIndex: 2, audioLanguage: "en", trackSignature: nil)
        XCTAssertEqual(audio.applied(over: nil), audio)

        let decoded = try decode(SubtitlePrefRequest.self, #"""
        { "subtitle_track_index": 4, "subtitle_mode": "always" }
        """#)
        XCTAssertEqual(decoded.subtitleLanguage, "")
        XCTAssertEqual(decoded.subtitleTrackIndex, 4)
        XCTAssertEqual(decoded.externalSubtitlePath, "")
        XCTAssertEqual(decoded.subtitleMode, "always")
        XCTAssertNil(decoded.trackSignature)
        XCTAssertNil(decoded.showForcedSubtitles)

        let stored = try decode(SubtitlePrefRequest.self, #"""
        { "subtitle_language": "en", "subtitle_track_index": 1, "external_subtitle_path": "/a.srt",
          "subtitle_mode": "forced", "show_forced_subtitles": true }
        """#)
        XCTAssertEqual(stored.showForcedSubtitles, true)

        let kept = decoded.applied(over: stored)
        XCTAssertEqual(kept.showForcedSubtitles, true)
        XCTAssertEqual(kept.subtitleTrackIndex, 4)
        XCTAssertEqual(kept.subtitleMode, "always")

        XCTAssertEqual(decoded.applied(over: nil), decoded)
        var explicit = decoded
        explicit.showForcedSubtitles = false
        XCTAssertEqual(explicit.applied(over: stored).showForcedSubtitles, false)
    }

    // MARK: - OnboardingModels.swift

    func testUnrenderableTourPurge() {
        let serverId = "server-\(UUID().uuidString)"
        UnrenderableOnboardingTourSuppression.set(
            serverId: serverId, localAccountId: "acc1", profileId: "p", tourId: "t"
        )

        // Another account's purge leaves the record alone.
        UnrenderableOnboardingTourSuppression.purge(localAccountId: "acc2", serverId: serverId, includingLegacy: false)
        XCTAssertEqual(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: serverId, localAccountId: "acc1", profileId: "p"
            ),
            "t"
        )

        // Another server's purge leaves it too.
        UnrenderableOnboardingTourSuppression.purge(localAccountId: "acc1", serverId: "other", includingLegacy: true)
        XCTAssertEqual(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: serverId, localAccountId: "acc1", profileId: "p"
            ),
            "t"
        )

        UnrenderableOnboardingTourSuppression.purge(localAccountId: "acc1", serverId: serverId, includingLegacy: false)
        XCTAssertNil(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: serverId, localAccountId: "acc1", profileId: "p"
            )
        )
    }

    func testUnrenderableTourPurgeLegacyRecord() throws {
        let serverId = "server-\(UUID().uuidString)"
        let legacy = try JSONSerialization.data(withJSONObject: [
            "serverId": serverId,
            "profileId": "p",
            "tourId": "t",
        ])
        SharedDefaults.shared.set(legacy, forKey: Self.suppressionKey)

        UnrenderableOnboardingTourSuppression.purge(localAccountId: "acc1", serverId: serverId, includingLegacy: false)
        XCTAssertNotNil(SharedDefaults.shared.data(forKey: Self.suppressionKey))

        UnrenderableOnboardingTourSuppression.purge(localAccountId: "acc1", serverId: serverId, includingLegacy: true)
        XCTAssertNil(SharedDefaults.shared.data(forKey: Self.suppressionKey))
    }

    func testUnrenderableTourMoveToSurvivor() {
        let dropped = "dropped-\(UUID().uuidString)"
        let survivor = "survivor-\(UUID().uuidString)"
        UnrenderableOnboardingTourSuppression.set(
            serverId: dropped, localAccountId: "acc1", profileId: "p", tourId: "t"
        )

        // A different server's record is not moved.
        UnrenderableOnboardingTourSuppression.move(
            fromServer: "unrelated", toServer: survivor, accounts: ["acc1"], legacyTarget: nil
        )
        XCTAssertEqual(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: dropped, localAccountId: "acc1", profileId: "p"
            ),
            "t"
        )

        UnrenderableOnboardingTourSuppression.move(
            fromServer: dropped, toServer: survivor, accounts: ["acc1"], legacyTarget: nil
        )
        XCTAssertEqual(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: survivor, localAccountId: "acc1", profileId: "p"
            ),
            "t"
        )
        XCTAssertNil(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: dropped, localAccountId: "acc1", profileId: "p"
            )
        )
    }

    func testUnrenderableTourMoveDropsRecordWhenAccountDidNotMove() {
        let dropped = "dropped-\(UUID().uuidString)"
        let survivor = "survivor-\(UUID().uuidString)"
        UnrenderableOnboardingTourSuppression.set(
            serverId: dropped, localAccountId: "acc1", profileId: "p", tourId: "t"
        )
        UnrenderableOnboardingTourSuppression.move(
            fromServer: dropped, toServer: survivor, accounts: ["someone-else"], legacyTarget: nil
        )
        XCTAssertNil(SharedDefaults.shared.data(forKey: Self.suppressionKey))
        XCTAssertNil(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: survivor, localAccountId: "acc1", profileId: "p"
            )
        )
    }

    func testUnrenderableTourMoveLegacyRecordFollowsLegacyTarget() throws {
        let dropped = "dropped-\(UUID().uuidString)"
        let survivor = "survivor-\(UUID().uuidString)"
        let legacy = try JSONSerialization.data(withJSONObject: [
            "serverId": dropped,
            "profileId": "p",
            "tourId": "t",
        ])
        SharedDefaults.shared.set(legacy, forKey: Self.suppressionKey)

        UnrenderableOnboardingTourSuppression.move(
            fromServer: dropped, toServer: survivor, accounts: [], legacyTarget: "legacy-acc"
        )
        XCTAssertEqual(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: survivor, localAccountId: "legacy-acc", profileId: "p"
            ),
            "t"
        )

        // A legacy record with no target goes.
        SharedDefaults.shared.set(legacy, forKey: Self.suppressionKey)
        UnrenderableOnboardingTourSuppression.move(
            fromServer: dropped, toServer: survivor, accounts: ["x"], legacyTarget: nil
        )
        XCTAssertNil(SharedDefaults.shared.data(forKey: Self.suppressionKey))
    }

    // MARK: - APIv2CatalogModels.swift

    func testCatalogLettersQueryCopiesScopeAndLettersLookups() throws {
        var query = APIv2CatalogQuery()
        query.libraryId = "3"
        query.type = "movie"
        let letters = APIv2CatalogLettersQuery(query)
        XCTAssertEqual(letters.libraryId, "3")
        XCTAssertEqual(letters.type, "movie")
        XCTAssertEqual(letters.match, query.match)
        XCTAssertEqual(letters.groups, query.groups)
        XCTAssertEqual(letters.order, query.order)

        let index = try decode(APIv2CatalogLetters.self, #"""
        {
          "total": 3,
          "letters": [
            { "letter": "A", "count": 2, "position": 0 },
            { "letter": "B", "count": 1, "position": 2 }
          ],
          "runs": [
            { "letter": "A", "position": 0 },
            { "letter": "B", "position": 2 }
          ]
        }
        """#)
        XCTAssertEqual(index.letter(at: 1), "A")
        XCTAssertEqual(index.letter(at: 2), "B")
        XCTAssertNil(index.letter(at: -1))
        XCTAssertEqual(index.position(of: "B"), 2)
        XCTAssertNil(index.position(of: "Z"))
    }

    // MARK: - APIv2CatalogReadModels.swift

    func testDiscoverRowDecodesOptionalTitleKeyLeniently() throws {
        let good = try decode(APIv2DiscoverRow.self, #"""
        { "type": "t", "title": "Row", "items": [], "title_key": "k", "title_args": { "a": "b" } }
        """#)
        XCTAssertEqual(good.type, "t")
        XCTAssertEqual(good.title, "Row")
        XCTAssertEqual(good.titleKey, "k")
        XCTAssertEqual(good.titleArgs, ["a": "b"])

        let malformed = try decode(APIv2DiscoverRow.self, #"""
        { "type": "t", "title": "Row", "items": [], "title_key": 5, "title_args": "x" }
        """#)
        XCTAssertNil(malformed.titleKey)
        XCTAssertNil(malformed.titleArgs)
    }

    // MARK: - APIv2CatalogReadProjection.swift

    func testItemDetailProjectionCommunityRating() throws {
        let wire = try decode(APIv2CatalogRead.CatalogItemDetail.self, #"""
        {
          "content_id": "movie:1", "type": "movie", "status": "available", "title": "T",
          "cast": [], "crew": [], "genres": [], "subtitles": [], "versions": [],
          "community_rating": { "average": 4.5, "count": 12 }
        }
        """#)
        let detail = try ItemDetail(catalog: wire)
        XCTAssertEqual(detail.communityRating?.average, 4.5)
        XCTAssertEqual(detail.communityRating?.count, 12)
        XCTAssertTrue(detail.showsForcedSubtitles)
    }

    func testWatchDetailProjectsPlaybackVariants() throws {
        let wire = try decode(APIv2CatalogRead.WatchDetail.self, #"""
        {
          "content_id": "movie:1", "type": "movie", "title": "T",
          "versions": [], "subtitles": [],
          "effective_show_forced_subtitles": false,
          "playback_variants": [
            { "variant_id": "v1", "edition_raw": "Cut", "edition_key": "cut",
              "presentation_kind": "multipart", "presentation_group_key": "g",
              "part_count": 2, "total_duration_seconds": 100, "default_file_id": "7",
              "parts": [
                { "part_index": 1, "default_file_id": "7", "total_duration_seconds": 50, "versions": [] }
              ] }
          ]
        }
        """#)
        let detail = try WatchDetail(v2: wire)
        XCTAssertFalse(detail.showsForcedSubtitles)
        let variant = try XCTUnwrap(detail.playbackVariants?.first)
        XCTAssertEqual(variant.variantId, "v1")
        XCTAssertEqual(variant.editionKey, "cut")
        XCTAssertEqual(variant.partCount, 2)
        XCTAssertEqual(variant.totalDuration, 100)
        XCTAssertEqual(variant.defaultFileId, 7)
        let part = try XCTUnwrap(variant.parts.first)
        XCTAssertEqual(part.partIndex, 1)
        XCTAssertEqual(part.defaultFileId, 7)
        XCTAssertEqual(part.totalDuration, 50)
        XCTAssertTrue(part.versions.isEmpty)

        let defaulted = try WatchDetail(v2: decode(APIv2CatalogRead.WatchDetail.self, #"""
        { "content_id": "m", "type": "movie", "title": "T", "versions": [], "subtitles": [] }
        """#))
        XCTAssertTrue(defaulted.showsForcedSubtitles)
        XCTAssertNil(defaulted.playbackVariants)
    }

    func testTrickplayProjectionRejectsZeroGeometry() throws {
        let wire = try decode(APIv2CatalogRead.WatchTrickplay.self, #"""
        {
          "file_id": "5", "interval_ms": 0, "thumbnail_width": 160, "thumbnail_height": 90,
          "tile_columns": 5, "tile_rows": 5, "thumbnail_count": 10, "sheets": [],
          "expires_at": "2026-01-02T03:04:05Z"
        }
        """#)
        XCTAssertThrowsError(try ServerTrickplay(v2: wire))
    }

    // MARK: - RequestsModels.swift

    func testRequestEnumFallbacks() throws {
        XCTAssertEqual(RequestOutcome.fallback, .unknown)
        XCTAssertEqual(RequestUserState.fallback, .unknown)
        XCTAssertEqual(RequestAvailability.fallback, .unknown)
        XCTAssertEqual(try decode(RequestOutcome.self, #""bogus""#), .unknown)
        XCTAssertEqual(try decode(RequestUserState.self, #""bogus""#), .unknown)
        XCTAssertEqual(try decode(RequestAvailability.self, #""bogus""#), .unknown)
    }

    func testDiscoverySectionIdentityIsItsKey() throws {
        let section = try decode(RequestDiscoverySection.self, #"""
        { "key": "trending_movies", "title": "Trending", "page": 1, "total_pages": 1,
          "total_results": 0, "results": [] }
        """#)
        XCTAssertEqual(section.id, "trending_movies")
        XCTAssertNil(section.nextPage)
    }

    func testMediaRequestDefaultsAndIsRemovable() {
        let epoch = Date(timeIntervalSince1970: 0)
        func make(outcome: RequestOutcome, targets: [RequestTarget]?) -> MediaRequest {
            MediaRequest(
                id: "r1",
                mediaType: .movie,
                tmdbId: 1,
                title: "T",
                year: nil,
                overview: nil,
                posterPath: nil,
                backdropPath: nil,
                status: .failed,
                outcome: outcome,
                state: nil,
                targets: targets,
                libraryContentId: nil,
                lastError: nil,
                createdAt: epoch,
                updatedAt: epoch,
                completedAt: nil
            )
        }
        let failed = make(outcome: .failed, targets: nil)
        XCTAssertNil(failed.approvedAt)
        XCTAssertNil(failed.requestedByUserId)
        XCTAssertNil(failed.requestedByProfileId)
        XCTAssertTrue(failed.isRemovable)

        let delivered = make(
            outcome: .failed,
            targets: [RequestTarget(quality: "1080p", status: .completed, lastError: nil)]
        )
        XCTAssertFalse(delivered.isRemovable)

        let undelivered = make(
            outcome: .failed,
            targets: [RequestTarget(quality: "1080p", status: .failed, lastError: "x")]
        )
        XCTAssertTrue(undelivered.isRemovable)
        XCTAssertFalse(make(outcome: .active, targets: nil).isRemovable)
    }
}
