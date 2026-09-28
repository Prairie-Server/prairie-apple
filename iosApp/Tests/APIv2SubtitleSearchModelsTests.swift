import Foundation
import XCTest
@testable import Prairie

/// API v2 subtitle search and download models, and how a download attempt is
/// resolved into what the player tells the viewer.
final class APIv2SubtitleSearchModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func stored(id: String = "sub-1", file: String = "42") throws -> APIv2StoredSubtitle {
        try decode(APIv2StoredSubtitle.self, """
        { "id": "\(id)", "media_file_id": "\(file)", "provider": "opensubtitles", "language": "en",
          "format": "srt", "release_name": "Movie.2024", "score": 91.5, "hearing_impaired": true,
          "created_at": "2026-01-01T00:00:00Z" }
        """)
    }

    private func subtitle(_ id: String) -> DownloadedSubtitle {
        DownloadedSubtitle(id: id, mediaFileId: 42, provider: "p", language: "en", format: "srt",
                           releaseName: "r", score: nil, hearingImpaired: nil, createdAt: nil)
    }

    func testProviderStatusStoredSubtitlesAndBodies() throws {
        func status(enabled: Bool = true, state: String = "available", allowed: Bool = true) throws -> APIv2SubtitleProviderStatus {
            try decode(APIv2SubtitleProviderStatus.self, """
            { "schema_version": 1, "enabled": \(enabled), "providers": ["opensubtitles"], "revision": "1",
              "state": "\(state)", "allowed": \(allowed) }
            """)
        }
        XCTAssertTrue(try status().isAvailable)
        XCTAssertFalse(try status(enabled: false).isAvailable)
        XCTAssertFalse(try status(state: "disabled").isAvailable)
        XCTAssertFalse(try status(allowed: false).isAvailable)

        let value = try stored().playerValue(mediaFileID: 42)
        XCTAssertEqual(value.id, "sub-1")
        XCTAssertEqual(value.mediaFileId, 42)
        XCTAssertEqual(value.score, 91.5)
        XCTAssertEqual(value.hearingImpaired, true)
        XCTAssertThrowsError(try stored(id: "").playerValue(mediaFileID: 42))
        XCTAssertThrowsError(try stored(file: "43").playerValue(mediaFileID: 42))

        let list = try decode(APIv2StoredSubtitles.self, #"{ "subtitles": [] }"#)
        XCTAssertEqual(try list.playerValues(mediaFileID: 42), [])
        let download = try decode(APIv2SubtitleDownloadResponse.self, """
        { "subtitle": { "id": "sub-2", "media_file_id": "42", "provider": "p", "language": "fr", "format": "ass",
          "release_name": "x", "score": 1, "hearing_impaired": false, "created_at": "c" } }
        """)
        XCTAssertEqual(try download.subtitle.playerValue(mediaFileID: 42).language, "fr")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let search = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(
            APIv2SubtitleSearchBody(SubtitleSearchBody(mediaFileId: 42, languages: ["en", "fr"])))) as? [String: Any])
        XCTAssertEqual(search["media_file_id"] as? String, "42")
        XCTAssertEqual(search["languages"] as? [String], ["en", "fr"])

        let result = SubtitleSearchResult(id: "os-1", provider: "opensubtitles", language: "en",
                                          releaseName: "Movie", format: "srt", score: 80, downloads: 5,
                                          hearingImpaired: false)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(
            APIv2SubtitleDownloadBody(SubtitleDownloadBody(from: result, mediaFileId: 42)))) as? [String: Any])
        XCTAssertEqual(body["subtitle_id"] as? String, "os-1")
        XCTAssertEqual(body["release_name"] as? String, "Movie")

        let response = try decode(APIv2SubtitleSearchResponse.self, """
        { "results": [{ "id": "os-1", "score": 80 }], "warnings": ["provider slow"] }
        """).playerValue
        XCTAssertEqual(response.results.map(\.id), ["os-1"])
        XCTAssertEqual(response.warnings, ["provider slow"])

        for error in [APIv2SubtitleRequestError.invalidMediaFile, .tooManyLanguages, .outcomeUnknownOwnerChanged] {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    func testDownloadOutcomeClassification() throws {
        XCTAssertNil(SubtitleDownloadOutcome.added.message)
        XCTAssertEqual(SubtitleDownloadOutcome.stored.message, SubtitleDownloadOutcome.storedMessage)
        XCTAssertEqual(SubtitleDownloadOutcome.unconfirmed.message, SubtitleDownloadOutcome.unconfirmedMessage)
        XCTAssertEqual(SubtitleDownloadOutcome.failed("nope").message, "nope")
        XCTAssertTrue(SubtitleDownloadOutcome.stored.holdsResult)
        XCTAssertTrue(SubtitleDownloadOutcome.unconfirmed.holdsResult)
        XCTAssertFalse(SubtitleDownloadOutcome.added.holdsResult)

        XCTAssertTrue(SubtitleDownloadOutcome.isUnconfirmed(APIv2SubtitleRequestError.outcomeUnknownOwnerChanged))
        XCTAssertTrue(SubtitleDownloadOutcome.isUnconfirmed(URLError(.networkConnectionLost)))
        XCTAssertFalse(SubtitleDownloadOutcome.isUnconfirmed(HTTPError.http(statusCode: 500, body: nil)))

        let problem = try decode(APIv2Problem.self, """
        { "type": "https://prairieserver.org/docs/api/v2/problems/not_found", "title": "Missing",
          "status": 404, "detail": "No such subtitle." }
        """)
        XCTAssertEqual(SubtitleDownloadOutcome.failureMessage(for: APIv2Error.serverUpdateRequired),
                       APIv2Error.serverUpdateRequired.localizedDescription)
        XCTAssertEqual(SubtitleDownloadOutcome.failureMessage(for: APIv2Error.problem(problem)),
                       APIv2Error.problem(problem).localizedDescription)
        XCTAssertEqual(SubtitleDownloadOutcome.failureMessage(for: HTTPError.http(statusCode: 500, body: nil)),
                       SubtitleDownloadOutcome.genericFailure)

        XCTAssertEqual(SubtitleDownloadOutcome.forDownloadError(URLError(.networkConnectionLost)), .unconfirmed)
        XCTAssertEqual(SubtitleDownloadOutcome.forDownloadError(APIv2Error.invalidSubtitleResponse), .stored)
        XCTAssertEqual(SubtitleDownloadOutcome.forDownloadError(HTTPError.http(statusCode: 500, body: nil)),
                       .failed(SubtitleDownloadOutcome.genericFailure))
    }

    @MainActor
    func testResolveWalksEveryHandoffStep() async {
        struct Failure: Error {}
        let good = subtitle("sub-1")
        let listing = [subtitle("sub-0"), good]

        let added = await SubtitleDownloadOutcome.resolve(
            download: { ("owner", good) }, relist: { _ in listing },
            isStillCurrent: { _ in true }, register: { list, position in list[position].id == "sub-1" })
        XCTAssertEqual(added, .added)

        let downloadFailed = await SubtitleDownloadOutcome.resolve(
            download: { () async throws -> (String, DownloadedSubtitle) in throw HTTPError.http(statusCode: 500, body: nil) },
            relist: { _ in listing }, isStillCurrent: { _ in true }, register: { _, _ in true })
        XCTAssertEqual(downloadFailed, .failed(SubtitleDownloadOutcome.genericFailure))

        let relistFailed = await SubtitleDownloadOutcome.resolve(
            download: { ("owner", good) }, relist: { _ in throw Failure() },
            isStillCurrent: { _ in true }, register: { _, _ in true })
        XCTAssertEqual(relistFailed, .stored)

        let ownerChanged = await SubtitleDownloadOutcome.resolve(
            download: { ("owner", good) }, relist: { _ in listing },
            isStillCurrent: { _ in false }, register: { _, _ in true })
        XCTAssertEqual(ownerChanged, .stored)

        let missing = await SubtitleDownloadOutcome.resolve(
            download: { ("owner", good) }, relist: { _ in [self.subtitle("other")] },
            isStillCurrent: { _ in true }, register: { _, _ in true })
        XCTAssertEqual(missing, .stored)

        let unregistered = await SubtitleDownloadOutcome.resolve(
            download: { ("owner", good) }, relist: { _ in listing },
            isStillCurrent: { _ in true }, register: { _, _ in false })
        XCTAssertEqual(unregistered, .stored)
    }
}
