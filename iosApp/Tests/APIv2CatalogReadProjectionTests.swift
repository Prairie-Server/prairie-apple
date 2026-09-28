import Foundation
import XCTest
@testable import Prairie

/// Projection of the API v2 catalog reads into the presentation models the
/// detail, season, episode and player screens consume. Every nested type is
/// populated so a field dropped or mis-mapped by the projection shows up here.
final class APIv2CatalogReadProjectionTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let fileVersionJSON = #"""
    {
      "added_at": "2026-01-02T03:04:05Z",
      "bitrate": 12000,
      "codec_audio": "eac3",
      "codec_video": "hevc",
      "container": "mkv",
      "duration": 7200,
      "edition_key": "directors",
      "edition_raw": "Director's Cut",
      "effective_audio_language": "en",
      "effective_audio_track_index": 1,
      "file_id": "42",
      "file_name": "movie.mkv",
      "file_size": 123456789,
      "hdr": true,
      "resolution": "2160p",
      "presentation_group_key": "g1",
      "presentation_kind": "multipart",
      "presentation_part_index": 1,
      "presentation_part_total": 2,
      "intro": { "start": 10, "end": 70 },
      "credits": { "start": 7000, "end": 7200 },
      "audio_tracks": [
        { "bit_depth": 24, "bitrate": 640, "channels": 6, "codec": "eac3", "default": true,
          "embedded_title": "Surround", "language": "en", "layout": "5.1(side)",
          "profile": "DD+", "sample_rate": 48000, "title": "English 5.1" }
      ],
      "video_tracks": [
        { "aspect_ratio": "16:9", "bit_depth": 10, "bitrate": 11000, "codec": "hevc",
          "color_primaries": "bt2020", "color_range": "tv", "color_space": "bt2020nc",
          "color_transfer": "smpte2084", "dolby_vision": "Profile 8.1",
          "dv_bl_compat_id_present": true, "dv_config_present": true, "frame_rate": "23.976",
          "height": 2160, "interlaced": false, "level": 153, "profile": "Main 10",
          "title": "Main", "video_range": "HDR", "width": 3840 }
      ],
      "subtitle_tracks": [
        { "codec": "subrip", "default": false, "embedded_title": "Forced", "external": true,
          "file_name": "/subs/movie.en.forced.srt", "forced": true, "hearing_impaired": false,
          "index": 3, "language": "en", "title": "English (Forced)" }
      ],
      "chapters": [
        { "end_seconds": 600, "index": 0, "source": "embedded", "start_seconds": 0,
          "thumbnail_thumbhash": "abc", "thumbnail_url": "https://cdn.example/ch0.jpg",
          "title": "Opening" }
      ]
    }
    """#

    private func itemDetailJSON(fileId: String = "42") -> String {
        let version = fileVersionJSON.replacingOccurrences(of: #""file_id": "42""#, with: #""file_id": "\#(fileId)""#)
        return #"""
        {
          "content_id": "movie:1",
          "type": "movie",
          "status": "available",
          "title": "The Movie",
          "sort_title": "Movie, The",
          "original_title": "Le Film",
          "original_language": "fr",
          "show_status": "ended",
          "year": 2024,
          "overview": "Things happen.",
          "tagline": "It happens.",
          "runtime": 120,
          "content_rating": "PG-13",
          "genres": ["Drama"],
          "keywords": ["heist"],
          "rating_imdb": 7.5,
          "rating_tmdb": 7.1,
          "rating_rt_critic": 88,
          "rating_rt_audience": 80,
          "imdb_id": "tt1",
          "tmdb_id": "11",
          "tvdb_id": "22",
          "studios": ["Studio"],
          "networks": ["Net"],
          "countries": ["FR"],
          "release_date": "2024-05-01",
          "first_air_date": "2024-05-01",
          "last_air_date": "2024-06-01",
          "poster_thumbhash": "p",
          "backdrop_thumbhash": "b",
          "poster_url": "https://cdn.example/poster.jpg",
          "backdrop_url": "https://cdn.example/backdrop.jpg",
          "logo_url": "https://cdn.example/logo.png",
          "season_count": 1,
          "series_id": "series:1",
          "series_title": "Series",
          "season_number": 1,
          "episode_number": 2,
          "episode_count": 10,
          "air_date": "2024-05-02",
          "is_specials": false,
          "pending_translation_language": "de",
          "effective_subtitle_mode": "forced",
          "effective_show_forced_subtitles": true,
          "effective_subtitle_track_signature": {
            "codec": "subrip", "forced": true, "hearing_impaired": false,
            "label": "English (Forced)", "language": "en", "source": "external"
          },
          "cast": [
            { "character": "Lead", "imdb_id": "nm1", "name": "Ada", "order": 0,
              "person_id": "person:1", "photo_thumbhash": "t", "photo_url": "https://cdn.example/ada.jpg",
              "tmdb_id": "101", "tvdb_id": "201" }
          ],
          "crew": [
            { "imdb_id": "nm2", "job": "Director", "name": "Grace", "person_id": "person:2",
              "photo_thumbhash": "g", "photo_url": "https://cdn.example/grace.jpg",
              "tmdb_id": "102", "tvdb_id": "202" }
          ],
          "user_data": {
            "duration_seconds": 7200, "in_progress_count": 1, "is_in_progress": true,
            "last_codec_video": "hevc", "last_file_id": "\#(fileId)", "last_hdr": true,
            "last_resolution": "2160p", "played": false, "position_seconds": 1800,
            "unplayed_count": 1, "watched_count": 0
          },
          "user_state": { "in_watchlist": true, "is_favorite": true, "played": false },
          "versions": [\#(version)],
          "playback_variants": [
            { "default_file_id": "\#(fileId)", "edition_key": "directors", "edition_raw": "Director's Cut",
              "part_count": 1, "presentation_group_key": "g1", "presentation_kind": "single",
              "total_duration": 7200, "variant_id": "v1",
              "parts": [
                { "default_file_id": "\#(fileId)", "part_index": 0, "total_duration": 7200,
                  "versions": [\#(version)] }
              ] }
          ],
          "subtitles": [
            { "codec": "ass", "forced": false, "hearing_impaired": true,
              "language": "ja", "source": "downloaded", "title": "Japanese SDH" }
          ],
          "intro": { "start": 5, "end": 65 },
          "credits": { "start": 7100, "end": 7200 },
          "overlay_summary": {
            "aspect_ratio": "2.39:1", "audio": "Atmos", "audio_channels": "7.1",
            "container": "mkv", "edition": "Director's Cut", "hdr": "DV",
            "multi_audio": true, "multi_sub": true, "release_type": "bluray",
            "resolution": "2160p", "video_codec": "hevc"
          },
          "audiobook": {
            "authors": [{ "name": "Author", "person_id": "person:3", "photo_thumbhash": "a",
                          "photo_url": "https://cdn.example/author.jpg" }],
            "narrators": [{ "name": "Narrator" }],
            "other_narrations": [{ "content_id": "book:2", "narrators": ["Other"],
                                   "title": "The Movie (Unabridged)", "year": 2020 }],
            "publisher": "Pub",
            "related": {
              "also_by_author": [{ "content_id": "book:3", "title": "Sequel", "year": 2025 }],
              "similar": [{ "content_id": "book:4", "poster_url": "https://cdn.example/b4.jpg",
                            "series_index": 2, "title": "Similar", "year": 2019 }]
            },
            "series": { "name": "Saga", "entries": [{ "content_id": "book:5", "series_index": 1,
                                                      "title": "First" }] },
            "total_duration_seconds": 36000
          },
          "videos": [
            { "is_official": true, "kind": "trailer", "language": "en", "name": "Trailer",
              "site": "youtube", "site_key": "abc123" }
          ],
          "extras": [
            { "content_id": "extra:1", "duration_seconds": 300, "file_id": 77,
              "kind": "behind_the_scenes", "title": "Making Of" }
          ]
        }
        """#
    }

    func testItemDetailProjectsEveryNestedField() throws {
        let wire = try decode(APIv2CatalogRead.CatalogItemDetail.self, itemDetailJSON())
        let detail = try ItemDetail(catalog: wire)

        XCTAssertEqual(detail.contentId, "movie:1")
        XCTAssertEqual(detail.type, "movie")
        XCTAssertEqual(detail.status, "available")
        XCTAssertEqual(detail.sortTitle, "Movie, The")
        XCTAssertEqual(detail.originalTitle, "Le Film")
        XCTAssertEqual(detail.originalLanguage, "fr")
        XCTAssertEqual(detail.showStatus, "ended")
        XCTAssertEqual(detail.year, 2024)
        XCTAssertEqual(detail.tagline, "It happens.")
        XCTAssertEqual(detail.runtime, 120)
        XCTAssertEqual(detail.contentRating, "PG-13")
        XCTAssertEqual(detail.genres, ["Drama"])
        XCTAssertEqual(detail.ratingImdb, 7.5)
        XCTAssertEqual(detail.ratingTmdb, 7.1)
        XCTAssertEqual(detail.ratingRtCritic, 88)
        XCTAssertEqual(detail.ratingRtAudience, 80)
        XCTAssertEqual(detail.imdbId, "tt1")
        XCTAssertEqual(detail.studios, ["Studio"])
        XCTAssertEqual(detail.networks, ["Net"])
        XCTAssertEqual(detail.countries, ["FR"])
        XCTAssertEqual(detail.lastAirDate, "2024-06-01")
        XCTAssertEqual(detail.seasonCount, 1)
        XCTAssertEqual(detail.seriesId, "series:1")
        XCTAssertEqual(detail.seasonNumber, 1)
        XCTAssertEqual(detail.episodeNumber, 2)
        XCTAssertEqual(detail.episodeCount, 10)
        XCTAssertEqual(detail.isSpecials, false)
        XCTAssertEqual(detail.pendingTranslationLanguage, "de")
        XCTAssertEqual(detail.posterUrl, "https://cdn.example/poster.jpg")
        XCTAssertEqual(detail.logoUrl, "https://cdn.example/logo.png")
        XCTAssertEqual(detail.effectiveSubtitleMode, "forced")
        XCTAssertEqual(detail.effectiveShowForcedSubtitles, true)
        XCTAssertEqual(detail.effectiveSubtitleTrackSignature?.label, "English (Forced)")
        XCTAssertEqual(detail.effectiveSubtitleTrackSignature?.forced, true)

        let cast = try XCTUnwrap(detail.cast?.first)
        XCTAssertEqual(cast.character, "Lead")
        XCTAssertEqual(cast.order, 0)
        XCTAssertEqual(cast.personId, "person:1")
        XCTAssertEqual(cast.photoUrl, "https://cdn.example/ada.jpg")
        let crew = try XCTUnwrap(detail.crew?.first)
        XCTAssertEqual(crew.job, "Director")
        XCTAssertEqual(crew.tvdbId, "202")

        let userData = try XCTUnwrap(detail.userData)
        XCTAssertEqual(userData.lastFileId, 42)
        XCTAssertEqual(userData.positionSeconds, 1800)
        XCTAssertEqual(userData.isInProgress, true)
        XCTAssertEqual(userData.lastHdr, true)
        XCTAssertEqual(detail.userState?.isFavorite, true)
        XCTAssertEqual(detail.userState?.inWatchlist, true)

        XCTAssertEqual(detail.subtitles?.first?.source, "downloaded")
        XCTAssertEqual(detail.subtitles?.first?.title, "Japanese SDH")
        XCTAssertEqual(detail.intro?.start, 5)
        XCTAssertEqual(detail.credits?.end, 7200)

        let overlay = try XCTUnwrap(detail.overlaySummary)
        XCTAssertEqual(overlay.edition, "Director's Cut")
        XCTAssertEqual(overlay.releaseType, "bluray")
        XCTAssertEqual(overlay.multiSub, true)
        XCTAssertEqual(overlay.aspectRatio, "2.39:1")

        let audiobook = try XCTUnwrap(detail.audiobook)
        XCTAssertEqual(audiobook.authors.first?.personId, "person:3")
        XCTAssertEqual(audiobook.narrators.map(\.name), ["Narrator"])
        XCTAssertEqual(audiobook.publisher, "Pub")
        XCTAssertEqual(audiobook.totalDurationSeconds, 36000)
        XCTAssertEqual(audiobook.series?.name, "Saga")
        XCTAssertEqual(audiobook.series?.entries.first?.seriesIndex, 1)
        XCTAssertEqual(audiobook.otherNarrations.first?.narrators, ["Other"])
        XCTAssertEqual(audiobook.otherNarrations.first?.year, 2020)
        XCTAssertEqual(audiobook.related?.alsoByAuthor.first?.year, 2025)
        XCTAssertEqual(audiobook.related?.similar.first?.seriesIndex, 2)
        XCTAssertEqual(audiobook.related?.similar.first?.posterUrl, "https://cdn.example/b4.jpg")

        let video = try XCTUnwrap(detail.videos?.first)
        XCTAssertEqual(video.siteKey, "abc123")
        XCTAssertTrue(video.isOfficial)
        let extra = try XCTUnwrap(detail.extras?.first)
        XCTAssertEqual(extra.fileId, 77)
        XCTAssertEqual(extra.durationSeconds, 300)

        let variant = try XCTUnwrap(detail.playbackVariants?.first)
        XCTAssertEqual(variant.variantId, "v1")
        XCTAssertEqual(variant.defaultFileId, 42)
        XCTAssertEqual(variant.partCount, 1)
        XCTAssertEqual(variant.totalDuration, 7200)
        XCTAssertEqual(variant.parts.first?.partIndex, 0)
        XCTAssertEqual(variant.parts.first?.defaultFileId, 42)
        XCTAssertEqual(variant.parts.first?.versions.first?.fileId, 42)

        try assertProjectedVersion(XCTUnwrap(detail.versions?.first))
    }

    private func assertProjectedVersion(_ version: FileVersion, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(version.fileId, 42, file: file, line: line)
        XCTAssertEqual(version.fileName, "movie.mkv", file: file, line: line)
        XCTAssertEqual(version.resolution, "2160p", file: file, line: line)
        XCTAssertEqual(version.hdr, true, file: file, line: line)
        XCTAssertEqual(version.fileSize, 123456789, file: file, line: line)
        XCTAssertEqual(version.duration, 7200, file: file, line: line)
        XCTAssertEqual(version.bitrate, 12000, file: file, line: line)
        XCTAssertEqual(version.editionDisplayLabel, "Director's Cut", file: file, line: line)
        XCTAssertEqual(version.editionKey, "directors", file: file, line: line)
        XCTAssertEqual(version.presentationKind, "multipart", file: file, line: line)
        XCTAssertEqual(version.presentationPartIndex, 1, file: file, line: line)
        XCTAssertEqual(version.presentationPartTotal, 2, file: file, line: line)
        XCTAssertEqual(version.effectiveAudioTrackIndex, 1, file: file, line: line)
        XCTAssertEqual(version.effectiveAudioLanguage, "en", file: file, line: line)
        XCTAssertEqual(version.intro?.end, 70, file: file, line: line)
        XCTAssertEqual(version.credits?.start, 7000, file: file, line: line)
        XCTAssertNil(version.trickplay, file: file, line: line)

        let audio = try XCTUnwrap(version.audioTracks?.first, file: file, line: line)
        XCTAssertNil(audio.index, file: file, line: line)
        XCTAssertEqual(audio.channels, 6, file: file, line: line)
        XCTAssertEqual(audio.channelLayout, "5.1(side)", file: file, line: line)
        XCTAssertEqual(audio.sampleRate, 48000, file: file, line: line)
        XCTAssertEqual(audio.embeddedTitle, "Surround", file: file, line: line)
        XCTAssertEqual(audio.isDefault, true, file: file, line: line)

        let video = try XCTUnwrap(version.videoTracks?.first, file: file, line: line)
        XCTAssertEqual(video.width, 3840, file: file, line: line)
        XCTAssertEqual(video.height, 2160, file: file, line: line)
        XCTAssertEqual(video.level, 153, file: file, line: line)
        XCTAssertEqual(video.bitDepth, 10, file: file, line: line)
        XCTAssertEqual(video.colorTransfer, "smpte2084", file: file, line: line)
        XCTAssertEqual(video.dolbyVision, "Profile 8.1", file: file, line: line)
        XCTAssertEqual(video.videoRange, "HDR", file: file, line: line)
        XCTAssertNil(video.language, file: file, line: line)

        let subtitle = try XCTUnwrap(version.subtitleTracks?.first, file: file, line: line)
        XCTAssertEqual(subtitle.index, 3, file: file, line: line)
        XCTAssertEqual(subtitle.forced, true, file: file, line: line)
        XCTAssertEqual(subtitle.external, true, file: file, line: line)
        XCTAssertEqual(subtitle.externalPath, "/subs/movie.en.forced.srt", file: file, line: line)
        XCTAssertEqual(subtitle.embeddedTitle, "Forced", file: file, line: line)

        let chapter = try XCTUnwrap(version.chapters?.first, file: file, line: line)
        XCTAssertEqual(chapter.index, 0, file: file, line: line)
        XCTAssertEqual(chapter.title, "Opening", file: file, line: line)
        XCTAssertEqual(chapter.endSeconds, 600, file: file, line: line)
        XCTAssertEqual(chapter.thumbnailUrl, "https://cdn.example/ch0.jpg", file: file, line: line)
        XCTAssertEqual(chapter.thumbnailThumbhash, "abc", file: file, line: line)
    }

    func testItemDetailRejectsOpaqueFileIDs() throws {
        for bad in ["file-abc", "0", "007", "-4"] {
            let wire = try decode(APIv2CatalogRead.CatalogItemDetail.self, itemDetailJSON(fileId: bad))
            XCTAssertThrowsError(try ItemDetail(catalog: wire), bad) { error in
                guard case APIv2Error.unsupportedCatalogReadValue = error else {
                    return XCTFail("unexpected error \(error) for \(bad)")
                }
            }
        }
    }

    func testWatchDetailProjectsWatchVersionsAndMarkers() throws {
        var watchVersion = fileVersionJSON
            .replacingOccurrences(of: #""duration": 7200"#, with: #""duration_seconds": 7200"#)
            .replacingOccurrences(of: #""intro": { "start": 10, "end": 70 }"#,
                                  with: #""intro": { "start_seconds": 10, "end_seconds": 70 }"#)
            .replacingOccurrences(of: #""credits": { "start": 7000, "end": 7200 }"#,
                                  with: #""credits": { "start_seconds": 7000, "end_seconds": 7200 }"#)
        watchVersion = watchVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = #"""
        {
          "content_id": "episode:1",
          "type": "episode",
          "title": "Pilot",
          "year": 2024,
          "overview": "First.",
          "series_id": "series:1",
          "series_title": "Series",
          "season_number": 1,
          "episode_number": 1,
          "effective_subtitle_language": "en",
          "effective_subtitle_mode": "always",
          "effective_show_forced_subtitles": false,
          "effective_subtitle_track_signature": { "forced": false, "hearing_impaired": true, "language": "en" },
          "intro": { "start_seconds": 1, "end_seconds": 31 },
          "credits": { "start_seconds": 2500, "end_seconds": 2600 },
          "user_data": { "in_progress_count": 0, "played": true, "unplayed_count": 0, "watched_count": 1 },
          "subtitles": [{ "forced": false, "hearing_impaired": false, "language": "en", "source": "embedded" }],
          "versions": [\#(watchVersion)]
        }
        """#
        let detail = try WatchDetail(v2: decode(APIv2CatalogRead.WatchDetail.self, json))
        XCTAssertEqual(detail.contentId, "episode:1")
        XCTAssertEqual(detail.year, 2024)
        XCTAssertEqual(detail.seriesTitle, "Series")
        XCTAssertEqual(detail.seasonNumber, 1)
        XCTAssertEqual(detail.episodeNumber, 1)
        XCTAssertEqual(detail.effectiveSubtitleLanguage, "en")
        XCTAssertEqual(detail.effectiveSubtitleMode, "always")
        XCTAssertEqual(detail.effectiveShowForcedSubtitles, false)
        XCTAssertEqual(detail.effectiveSubtitleTrackSignature?.hearingImpaired, true)
        XCTAssertEqual(detail.intro?.start, 1)
        XCTAssertEqual(detail.credits?.end, 2600)
        XCTAssertEqual(detail.userData?.played, true)
        XCTAssertEqual(detail.subtitles?.first?.source, "embedded")
        try assertProjectedVersion(XCTUnwrap(detail.versions.first))
    }

    func testSeasonsEpisodesPersonAndLibraryProjection() throws {
        let seasons = try SeasonsResponse(catalog: decode([APIv2CatalogRead.Season].self, #"""
        [{ "air_date": "2024-01-01", "content_id": "season:1", "episode_count": 8, "is_specials": false,
           "overview": "S1", "poster_thumbhash": "s", "poster_url": "https://cdn.example/s1.jpg",
           "season_number": 1, "title": "Season 1",
           "user_data": { "in_progress_count": 1, "played": false, "unplayed_count": 6, "watched_count": 2 } }]
        """#))
        let season = try XCTUnwrap(seasons.seasons.first)
        XCTAssertEqual(season.seasonNumber, 1)
        XCTAssertEqual(season.episodeCount, 8)
        XCTAssertEqual(season.posterUrl, "https://cdn.example/s1.jpg")
        XCTAssertEqual(season.userData?.watchedCount, 2)
        XCTAssertEqual(season.userData?.unplayedCount, 6)
        XCTAssertEqual(season.userData?.inProgressCount, 1)

        let episodes = try EpisodesResponse(catalog: decode([APIv2CatalogRead.Episode].self, #"""
        [{ "air_date": "2024-01-02", "content_id": "episode:1", "episode_number": 3,
           "files": [{ "audio_channels": 6, "codec_video": "h264", "container": "mp4",
                       "file_id": "9", "file_size": 1000, "hdr": false, "resolution": "1080p" }],
           "imdb_id": "tt2", "overview": "E3", "runtime": 45, "season_number": 1,
           "still_thumbhash": "e", "still_url": "https://cdn.example/e3.jpg", "title": "Three",
           "tmdb_id": "33", "tvdb_id": "44",
           "user_data": { "in_progress_count": 0, "last_file_id": "9", "played": true,
                          "unplayed_count": 0, "watched_count": 1 } }]
        """#))
        let episode = try XCTUnwrap(episodes.episodes.first)
        XCTAssertEqual(episode.episodeNumber, 3)
        XCTAssertEqual(episode.runtime, 45)
        XCTAssertEqual(episode.stillUrl, "https://cdn.example/e3.jpg")
        XCTAssertEqual(episode.userData?.lastFileId, 9)
        let file = try XCTUnwrap(episode.files?.first)
        XCTAssertEqual(file.fileId, 9)
        XCTAssertEqual(file.audioChannels, 6)
        XCTAssertEqual(file.fileSize, 1000)
        XCTAssertEqual(file.hdr, false)

        let person = try Person(catalog: decode(APIv2CatalogRead.Person.self, #"""
        { "bio": "Bio", "birth_date": "1900-01-01", "birthplace": "Here", "death_date": "1990-01-01",
          "homepage": "https://ada.example", "id": "person:1", "imdb_id": "nm1", "name": "Ada",
          "photo_thumbhash": "a", "photo_url": "https://cdn.example/ada.jpg", "plex_guid": "plex://1",
          "tmdb_id": "1", "tvdb_id": "2" }
        """#))
        XCTAssertEqual(person.id, "person:1")
        XCTAssertEqual(person.bio, "Bio")
        XCTAssertEqual(person.birthplace, "Here")
        XCTAssertEqual(person.photoUrl, "https://cdn.example/ada.jpg")

        let library = try Library(v2: decode(APIv2UserLibrary.self, #"""
        { "id": "5", "name": "Movies", "type": "movies", "sort_order": 2, "poster_url": "https://cdn.example/l.jpg" }
        """#))
        XCTAssertEqual(library.id, 5)
        XCTAssertEqual(library.sortOrder, 2)
        XCTAssertTrue(library.isMovieLibrary)
        XCTAssertThrowsError(try Library(v2: decode(APIv2UserLibrary.self, #"""
        { "id": "lib-5", "name": "Movies", "type": "movies", "sort_order": 2 }
        """#)))
    }

    func testCatalogReadCollectionRejectsPartialPages() throws {
        let complete = try decode(APIv2CatalogReadCollection<APIv2CatalogRead.Person>.self, #"""
        { "items": [{ "id": "person:1", "name": "Ada" }], "page": { "has_more": false } }
        """#)
        XCTAssertEqual(try complete.completeItems().map(\.name), ["Ada"])

        let unpaged = try decode(APIv2CatalogReadCollection<APIv2CatalogRead.Person>.self, #"""
        { "items": [] }
        """#)
        XCTAssertEqual(try unpaged.completeItems().count, 0)

        for page in [#"{ "has_more": true }"#, #"{ "has_more": false, "next_cursor": "c2" }"#] {
            let partial = try decode(APIv2CatalogReadCollection<APIv2CatalogRead.Person>.self,
                                     #"{ "items": [], "page": \#(page) }"#)
            XCTAssertThrowsError(try partial.completeItems()) { error in
                guard case APIv2Error.incompleteCatalogRead = error else {
                    return XCTFail("unexpected error \(error)")
                }
            }
        }
    }
}
