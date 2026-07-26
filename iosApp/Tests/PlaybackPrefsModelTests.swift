//
//  PlaybackPrefsModelTests.swift
//  PrairieTests
//

import XCTest
import Foundation
@testable import Prairie

final class PlaybackPrefsModelTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    func testSubtitleTrackSignatureDefaults() throws {
        let sig = try decode(SubtitleTrackSignature.self, """
        { "language": "en", "codec": "subrip" }
        """)
        XCTAssertEqual(sig.language, "en")
        XCTAssertFalse(sig.forced)
        XCTAssertFalse(sig.hearingImpaired)
    }

    func testAudioTrackSignatureRoundTrip() throws {
        let sig = try decode(AudioTrackSignature.self, """
        {
          "language": "en",
          "title": "English",
          "embedded_title": "Atmos",
          "codec": "truehd",
          "layout": "5.1",
          "channels": 6,
          "default": true
        }
        """)
        XCTAssertEqual(sig.channels, 6)
        XCTAssertEqual(sig.embeddedTitle, "Atmos")
        XCTAssertTrue(sig.isDefault)

        // Round-trip with the same snake_case strategies HTTPClient uses.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(sig)
        let again = try decoder().decode(AudioTrackSignature.self, from: data)
        XCTAssertEqual(again.embeddedTitle, "Atmos")
        XCTAssertTrue(again.isDefault)
    }

    func testPlaybackLanguageOptionLabels() {
        XCTAssertEqual(PlaybackLanguageOption.label(forCode: "en"), "English")
        XCTAssertEqual(PlaybackLanguageOption.label(forCode: "original"), "Original Language")
        XCTAssertEqual(PlaybackLanguageOption.label(forCode: "xx"), "XX")
        XCTAssertEqual(PlaybackLanguageOption.all.count, 12)
        XCTAssertEqual(PlaybackPrefSentinel.inherit, "__inherit__")
        XCTAssertEqual(PlaybackPrefSentinel.none, "__none__")
    }

    func testSubtitleModeDisplayCopy() {
        XCTAssertEqual(SubtitleMode.auto.displayLabel, "Auto")
        XCTAssertFalse(SubtitleMode.always.displayDescription.isEmpty)
        XCTAssertEqual(SubtitleMode.off.rawValue, "off")
    }

    func testLibraryPlaybackPrefsDecode() throws {
        let prefs = try decode(LibraryPlaybackPrefsResponse.self, """
        {
          "preferences": [
            {
              "profile_id": "p",
              "library_id": 3,
              "audio_language": "en",
              "subtitle_language": "es",
              "subtitle_mode": "always",
              "show_forced_subtitles": true
            }
          ]
        }
        """)
        XCTAssertEqual(prefs.preferences.count, 1)
        XCTAssertEqual(prefs.preferences[0].subtitleModeEnum, .always)
        XCTAssertEqual(prefs.preferences[0].id, 3)
    }

    func testLibraryPlaybackPrefsEmptyDefaults() throws {
        let prefs = try decode(LibraryPlaybackPrefsResponse.self, "{}")
        XCTAssertTrue(prefs.preferences.isEmpty)
    }

    func testSubtitleAndAudioPrefTolerantDefaults() throws {
        let sub = try decode(SubtitlePref.self, """
        { "series_id": "s1", "track_signature": { "language": "ja" } }
        """)
        XCTAssertEqual(sub.seriesId, "s1")
        XCTAssertEqual(sub.subtitleTrackIndex, -1)
        XCTAssertEqual(sub.trackSignature?.language, "ja")
        XCTAssertNil(sub.subtitleModeEnum)

        let audio = try decode(AudioPref.self, """
        { "series_id": "s1", "audio_language": "en" }
        """)
        XCTAssertEqual(audio.audioTrackIndex, -1)
        XCTAssertEqual(audio.audioLanguage, "en")
    }

    func testLibraryPlaybackPrefMissingProfileId() throws {
        let pref = try decode(LibraryPlaybackPref.self, """
        { "library_id": 9, "subtitle_mode": "nope" }
        """)
        XCTAssertEqual(pref.profileId, "")
        XCTAssertNil(pref.subtitleModeEnum)
    }
}
