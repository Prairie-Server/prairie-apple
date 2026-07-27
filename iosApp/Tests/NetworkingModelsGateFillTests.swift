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
          "edition": "  theatrical  ",
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
}
