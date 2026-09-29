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
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(encoded["embedded_title"] as? String, "Atmos")
        XCTAssertNil(encoded["embeddedTitle"])
        let again = try decoder().decode(AudioTrackSignature.self, from: data)
        XCTAssertEqual(again.embeddedTitle, "Atmos")
        XCTAssertTrue(again.isDefault)
    }

    func testPlaybackLanguageOptionLabels() {
        XCTAssertEqual(PlaybackLanguageOption.label(forCode: "en"), "English")
        XCTAssertEqual(PlaybackLanguageOption.label(forCode: "original"), "Original Language")
        XCTAssertEqual(PlaybackLanguageOption.label(forCode: "xx"), "XX")
        // `all` is the contract suggested-values floor for subtitle language —
        // pin to the generated catalog, not a stale hard-coded length.
        let contractFloor = SettingPresentationMetadata.suggestedValues(
            for: .playbackSubtitleLanguage
        )
        XCTAssertEqual(PlaybackLanguageOption.all.count, contractFloor.count)
        XCTAssertEqual(
            Set(PlaybackLanguageOption.all.map(\.code)),
            Set(contractFloor)
        )
        XCTAssertEqual(PlaybackPrefSentinel.inherit, "__inherit__")
        XCTAssertEqual(PlaybackPrefSentinel.none, "__none__")
    }

    func testSubtitleModeDisplayCopy() {
        XCTAssertEqual(SubtitleMode.auto.displayLabel, "Auto")
        XCTAssertFalse(SubtitleMode.always.displayDescription.isEmpty)
        XCTAssertEqual(SubtitleMode.off.rawValue, "off")
    }
}
