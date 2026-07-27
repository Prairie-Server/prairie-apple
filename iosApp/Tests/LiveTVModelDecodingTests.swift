//
//  LiveTVModelDecodingTests.swift
//  PrairieTests
//
//  Wire-decoding tests for Live TV models. Decodes raw snake_case JSON
//  exactly as `HTTPClient` does (`.convertFromSnakeCase` + ISO-8601 dates).
//

import XCTest
import Foundation
@testable import Prairie

final class LiveTVModelDecodingTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        HTTPClient.makeJSONDecoder()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    func testChannelFullDecodeAndDisplayHelpers() throws {
        let channel = try decode(LiveTVChannel.self, """
        {
          "id": "ch-1",
          "tuner_id": "tuner-a",
          "number": "4.1",
          "number_override": "4.1-HD",
          "callsign": "KXYZ-HD",
          "name": "KXYZ Digital",
          "logo_url": "https://example.test/logo.png",
          "hd": true,
          "enabled": true,
          "stream_url": "http://hdhr/auto/v4.1",
          "guide_station_id": "station-9"
        }
        """)
        XCTAssertEqual(channel.id, "ch-1")
        XCTAssertEqual(channel.tunerId, "tuner-a")
        XCTAssertEqual(channel.displayNumber, "4.1-HD")
        XCTAssertEqual(channel.displayName, "KXYZ-HD")
        XCTAssertTrue(channel.hd)
        XCTAssertTrue(channel.enabled)
    }

    func testChannelDisplayFallsBackWithoutCallsignOrOverride() throws {
        let channel = try decode(LiveTVChannel.self, """
        {
          "id": "ch-2",
          "tuner_id": "tuner-a",
          "number": "7.1",
          "callsign": "",
          "name": "Local 7",
          "logo_url": "",
          "hd": false,
          "enabled": true,
          "stream_url": "",
          "guide_station_id": ""
        }
        """)
        XCTAssertEqual(channel.displayNumber, "7.1")
        XCTAssertEqual(channel.displayName, "Local 7")
    }

    func testChannelDisplayFallsBackToNumberWhenLabelsAreBlank() throws {
        let channel = try decode(LiveTVChannel.self, """
        {
          "id": "ch-3",
          "tuner_id": "tuner-a",
          "number": "9.2",
          "number_override": "   ",
          "callsign": "   ",
          "name": "   ",
          "logo_url": "",
          "hd": false,
          "enabled": true,
          "stream_url": "",
          "guide_station_id": ""
        }
        """)
        XCTAssertEqual(channel.displayNumber, "9.2")
        XCTAssertEqual(channel.displayName, "9.2")
    }

    func testChannelsResponseDecode() throws {
        let response = try decode(LiveTVChannelsResponse.self, """
        {
          "channels": [
            {
              "id": "a",
              "tuner_id": "t",
              "number": "1",
              "callsign": "A",
              "name": "A",
              "logo_url": "",
              "hd": false,
              "enabled": true,
              "stream_url": "",
              "guide_station_id": ""
            }
          ]
        }
        """)
        XCTAssertEqual(response.channels.count, 1)
        XCTAssertEqual(response.channels[0].id, "a")
    }

    func testGuideProgramAndSessionStartDecode() throws {
        let program = try decode(LiveTVProgram.self, """
        {
          "id": "prog-1",
          "channel_id": "ch-1",
          "series_id": "series-1",
          "start": "2026-07-25T18:00:00Z",
          "stop": "2026-07-25T19:00:00Z",
          "title": "Evening News",
          "subtitle": "Late edition",
          "description": "Local news",
          "season": 1,
          "episode": 12,
          "genres": ["News"],
          "image_url": "",
          "is_new": true,
          "is_live": false
        }
        """)
        XCTAssertEqual(program.id, "prog-1")
        XCTAssertEqual(program.channelId, "ch-1")
        XCTAssertEqual(program.displayTitle, "Evening News")
        XCTAssertEqual(program.season, 1)
        XCTAssertEqual(program.episode, 12)
        XCTAssertTrue(program.isNew)

        let session = try decode(LiveTVSessionStartResponse.self, """
        {
          "session_id": "sess-1",
          "playback_ticket": "ticket-1",
          "hls_url": "https://server.test/livetv/sess-1/index.m3u8",
          "stream_url": "http://hdhr/auto/v4.1",
          "transport": "hls",
          "note": "transcoding"
        }
        """)
        XCTAssertEqual(session.sessionId, "sess-1")
        XCTAssertEqual(session.playbackTicket, "ticket-1")
        XCTAssertEqual(session.playableURLString, "https://server.test/livetv/sess-1/index.m3u8")
        XCTAssertTrue(session.isHLS)
        XCTAssertEqual(session.transport, "hls")
        XCTAssertEqual(session.note, "transcoding")
    }

    func testSessionStartMpegtsTransportAndPlayableURLFallback() throws {
        let session = try decode(LiveTVSessionStartResponse.self, """
        {
          "session_id": "sess-2",
          "playback_ticket": "ticket-2",
          "hls_url": "",
          "stream_url": "/api/v1/livetv/sessions/sess-2/stream",
          "transport": "mpegts"
        }
        """)
        XCTAssertEqual(session.playableURLString, "/api/v1/livetv/sessions/sess-2/stream")
        XCTAssertFalse(session.isHLS)
    }

    func testSessionStartMpegtsTransportWithLiveHlsBridgeIsHLS() throws {
        let session = try decode(LiveTVSessionStartResponse.self, """
        {
          "session_id": "sess-bridge",
          "playback_ticket": "ticket-bridge",
          "hls_url": "/api/v1/livetv/live-hls/ticket-bridge/index.m3u8",
          "stream_url": "/api/v1/livetv/sessions/sess-bridge/stream",
          "transport": "mpegts"
        }
        """)
        XCTAssertTrue(session.isHLS)
    }

    func testSessionStartInfersHLSFromManifestSuffix() throws {
        let session = try decode(LiveTVSessionStartResponse.self, """
        {
          "session_id": "sess-3",
          "playback_ticket": "ticket-3",
          "hls_url": "/api/v1/livetv/sessions/sess-3/index.m3u8",
          "stream_url": "/api/v1/livetv/sessions/sess-3/index.m3u8"
        }
        """)
        XCTAssertTrue(session.isHLS)
    }

    func testLiveTVURLResolverResolvesRelativeAPIPaths() {
        let url = LiveTVURLResolver.resolve(
            "/api/v1/livetv/sessions/s1/stream",
            serverBaseURL: "https://server.test"
        )
        XCTAssertEqual(url?.absoluteString, "https://server.test/api/v1/livetv/sessions/s1/stream")
    }

    func testLiveTVURLResolverAppendsTokenAndProfileIdForSameOrigin() throws {
        let url = try XCTUnwrap(LiveTVURLResolver.resolve(
            "/api/v1/livetv/live-hls/t1/index.m3u8",
            serverBaseURL: "https://server.test",
            accessToken: "access-tok",
            profileId: "profile-1"
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "server.test")
        XCTAssertEqual(components.path, "/api/v1/livetv/live-hls/t1/index.m3u8")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["token"], "access-tok")
        XCTAssertEqual(query["profile_id"], "profile-1")
    }

    func testLiveTVURLResolverDoesNotAttachAuthToCrossOriginURLs() {
        let url = LiveTVURLResolver.resolve(
            "https://cdn.test/live/index.m3u8",
            serverBaseURL: "https://server.test",
            accessToken: "access-tok",
            profileId: "profile-1"
        )
        XCTAssertEqual(url?.absoluteString, "https://cdn.test/live/index.m3u8")
    }

    func testLiveTVURLResolverPrefixesBarePathsWithApiV1() {
        let url = LiveTVURLResolver.resolve(
            "livetv/sessions/s1/stream",
            serverBaseURL: "https://server.test/"
        )
        XCTAssertEqual(url?.absoluteString, "https://server.test/api/v1/livetv/sessions/s1/stream")
    }

    func testLiveTVURLResolverPassesThroughAbsoluteURLs() {
        let url = LiveTVURLResolver.resolve(
            "https://cdn.test/live/index.m3u8",
            serverBaseURL: "https://server.test"
        )
        XCTAssertEqual(url?.absoluteString, "https://cdn.test/live/index.m3u8")
    }

    func testProgramDisplayTitleAndNowNextDefaults() throws {
        let program = try decode(LiveTVProgram.self, """
        {
          "id": "prog-blank",
          "channel_id": "ch-1",
          "series_id": "",
          "start": "2026-07-25T18:00:00Z",
          "stop": "2026-07-25T19:00:00Z",
          "title": "   ",
          "subtitle": "",
          "description": "",
          "genres": [],
          "image_url": "",
          "is_new": false,
          "is_live": true
        }
        """)
        XCTAssertEqual(program.displayTitle, "Untitled")

        let slot = LiveTVNowNext()
        XCTAssertNil(slot.now)
        XCTAssertNil(slot.next)
    }

    func testRecordingDecode() throws {
        let recording = try decode(LiveTVRecording.self, """
        {
          "id": "rec-1",
          "program_id": "prog-1",
          "channel_id": "ch-1",
          "status": "scheduled",
          "start": "2026-07-25T20:00:00Z",
          "stop": "2026-07-25T21:00:00Z",
          "title": "Movie Night"
        }
        """)
        XCTAssertEqual(recording.id, "rec-1")
        XCTAssertEqual(recording.status, "scheduled")
        XCTAssertEqual(recording.title, "Movie Night")
    }

    func testScheduleRecordingInputEncodesProgramOnly() throws {
        let input = LiveTVScheduleRecordingInput(programId: "prog-1")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(input)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["program_id"] as? String, "prog-1")
        XCTAssertEqual(object.count, 1)
    }

    func testNowNextMapPicksCurrentAndNext() {
        let cal = ISO8601DateFormatter()
        cal.formatOptions = [.withInternetDateTime]
        let t0 = cal.date(from: "2026-07-25T18:00:00Z")!
        let t1 = cal.date(from: "2026-07-25T19:00:00Z")!
        let t2 = cal.date(from: "2026-07-25T20:00:00Z")!
        let t3 = cal.date(from: "2026-07-25T21:00:00Z")!
        let now = cal.date(from: "2026-07-25T18:30:00Z")!

        let programs = [
            LiveTVProgram(
                id: "a", channelId: "ch", sourceId: nil, seriesId: "",
                externalId: nil, start: t0, stop: t1, title: "Now Show",
                subtitle: "", description: "", season: nil, episode: nil,
                genres: [], imageUrl: "", isNew: false, isLive: false
            ),
            LiveTVProgram(
                id: "b", channelId: "ch", sourceId: nil, seriesId: "",
                externalId: nil, start: t1, stop: t2, title: "Next Show",
                subtitle: "", description: "", season: nil, episode: nil,
                genres: [], imageUrl: "", isNew: false, isLive: false
            ),
            LiveTVProgram(
                id: "c", channelId: "ch", sourceId: nil, seriesId: "",
                externalId: nil, start: t2, stop: t3, title: "Later",
                subtitle: "", description: "", season: nil, episode: nil,
                genres: [], imageUrl: "", isNew: false, isLive: false
            ),
        ]

        let map = LiveTVChannelListViewModel.nowNextMap(programs: programs, at: now)
        XCTAssertEqual(map["ch"]?.now?.id, "a")
        XCTAssertEqual(map["ch"]?.next?.id, "b")
    }

    func testProgramsForChannelOmitsEnded() {
        let cal = ISO8601DateFormatter()
        cal.formatOptions = [.withInternetDateTime]
        let t0 = cal.date(from: "2026-07-25T18:00:00Z")!
        let t1 = cal.date(from: "2026-07-25T19:00:00Z")!
        let t2 = cal.date(from: "2026-07-25T20:00:00Z")!
        let now = cal.date(from: "2026-07-25T19:15:00Z")!

        let programs = [
            LiveTVProgram(
                id: "ended", channelId: "ch", sourceId: nil, seriesId: "",
                externalId: nil, start: t0, stop: t1, title: "Ended",
                subtitle: "", description: "", season: nil, episode: nil,
                genres: [], imageUrl: "", isNew: false, isLive: false
            ),
            LiveTVProgram(
                id: "airing", channelId: "ch", sourceId: nil, seriesId: "",
                externalId: nil, start: t1, stop: t2, title: "Airing",
                subtitle: "", description: "", season: nil, episode: nil,
                genres: [], imageUrl: "", isNew: false, isLive: false
            ),
        ]
        let visible = LiveTVChannelListViewModel.activeOrUpcomingPrograms(
            programs,
            channelId: "ch",
            at: now
        )
        XCTAssertEqual(visible.map(\.id), ["airing"])
    }
}
