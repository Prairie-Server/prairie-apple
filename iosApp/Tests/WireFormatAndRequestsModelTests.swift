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

    func testFeatureStatusAndCreateInputEncode() throws {
        let status = try decode(RequestsFeatureStatus.self, """
        { "requests_enabled": true, "state": "available", "allowed": true }
        """)
        XCTAssertTrue(status.requestsEnabled)
        XCTAssertTrue(status.isAvailable)

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
