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

    func testChannelsItemsEnvelopeDecodeToleratesMissingFields() throws {
        let response = try decode(LiveTVItemsResponse<LiveTVChannel>.self, """
        {
          "items": [
            {
              "id": "a",
              "tuner_id": "t",
              "number": "1",
              "callsign": "A",
              "name": "A",
              "logo_url": "",
              "hd": false,
              "enabled": true,
              "guide_station_id": ""
            },
            { "id": "b", "future_field": 1 }
          ]
        }
        """)
        XCTAssertEqual(response.items.map(\.id), ["a", "b"])
        XCTAssertEqual(response.items[1].number, "")
        XCTAssertTrue(response.items[1].enabled)
        XCTAssertEqual(try decode(LiveTVItemsResponse<LiveTVChannel>.self, "{}").items.count, 0)
    }

    func testGuideItemsEnvelopeAndProgramDecode() throws {
        let guide = try decode(LiveTVGuideResponse.self, """
        {
          "items": [
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
            },
            {
              "id": "prog-2",
              "channel_id": "ch-1",
              "start": "2026-07-25T19:00:00Z",
              "stop": "2026-07-25T20:00:00Z"
            }
          ],
          "start": "2026-07-25T18:00:00Z",
          "end": "2026-07-26T06:00:00Z"
        }
        """)
        XCTAssertEqual(guide.items.count, 2)
        XCTAssertNotNil(guide.start)
        let program = guide.items[0]
        XCTAssertEqual(program.id, "prog-1")
        XCTAssertEqual(program.channelId, "ch-1")
        XCTAssertEqual(program.displayTitle, "Evening News")
        XCTAssertEqual(program.season, 1)
        XCTAssertEqual(program.episode, 12)
        XCTAssertTrue(program.isNew)
        XCTAssertEqual(guide.items[1].displayTitle, "Untitled")
        XCTAssertEqual(guide.items[1].genres, [])
    }

    func testSessionStartDecodesV2StreamURL() throws {
        let session = try decode(LiveTVSessionStartResponse.self, """
        {
          "session_id": "sess-1",
          "channel_id": "ch-1",
          "playback_ticket": "ticket-1",
          "stream_url": "/api/v1/livetv/live-hls/ticket-1/index.m3u8?st=abc",
          "transport": "hls",
          "note": "transcoding",
          "status": "active",
          "created_at": "2026-07-25T18:00:00Z",
          "stale_after_seconds": 90
        }
        """)
        XCTAssertEqual(session.sessionId, "sess-1")
        XCTAssertEqual(session.channelId, "ch-1")
        XCTAssertEqual(session.playbackTicket, "ticket-1")
        XCTAssertEqual(session.playableURLString, "/api/v1/livetv/live-hls/ticket-1/index.m3u8?st=abc")
        XCTAssertTrue(session.isHLS)
        XCTAssertEqual(session.note, "transcoding")
        XCTAssertEqual(session.staleAfterSeconds, 90)
    }

    func testSessionStartMpegtsTransport() throws {
        let session = try decode(LiveTVSessionStartResponse.self, """
        {
          "session_id": "sess-2",
          "stream_url": "/api/v1/livetv/sessions/sess-2/stream",
          "transport": "mpegts"
        }
        """)
        XCTAssertEqual(session.playableURLString, "/api/v1/livetv/sessions/sess-2/stream")
        XCTAssertFalse(session.isHLS)
        XCTAssertNil(session.playbackTicket)
    }

    func testSessionStartWithoutStreamURLIsNotPlayable() throws {
        let session = try decode(LiveTVSessionStartResponse.self, #"{"session_id": "sess-3"}"#)
        XCTAssertEqual(session.playableURLString, "")
    }

    func testSessionStartBodyNestsClientCapabilities() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(LiveTVSessionStartInput(clientCapabilities: .avPlayer))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let caps = try XCTUnwrap(object["client_capabilities"] as? [String: Any])
        XCTAssertEqual(caps["codecs_video"] as? [String], ["h264", "hevc"])
        XCTAssertEqual(caps["codecs_audio"] as? [String], ["aac", "ac3", "eac3"])
        XCTAssertEqual(caps["max_audio_channels"] as? Int, 6)
        XCTAssertNotNil(caps["audio_passthrough_codecs"])
        XCTAssertNotNil(caps["max_resolution"])
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
        XCTAssertNotNil(recording.start)
    }

    func testRecordingsItemsEnvelopeToleratesMissingWindow() throws {
        let response = try decode(LiveTVItemsResponse<LiveTVRecording>.self, """
        {
          "items": [
            {
              "id": "rec-2",
              "channel_id": "ch-1",
              "profile_id": "p-1",
              "status": "failed",
              "title": "News",
              "last_error": "tuner busy"
            }
          ]
        }
        """)
        let recording = try XCTUnwrap(response.items.first)
        XCTAssertNil(recording.start)
        XCTAssertNil(recording.stop)
        XCTAssertEqual(recording.profileId, "p-1")
        XCTAssertEqual(recording.lastError, "tuner busy")
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
