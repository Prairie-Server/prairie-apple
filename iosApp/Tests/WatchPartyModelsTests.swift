import Foundation
import XCTest
@testable import Prairie

/// Watch Party wire models: forward-compatible enums, capability gating,
/// strict room validation, numeric-or-string ids, and the member-state and
/// picker shapes.
final class WatchPartyModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func roomJSON(roomId: String = "room-1", selectionRevision: Int = 2, generation: Int = 5,
                          anchor: String = "12.5", fileId: String = #""42""#) -> String {
        """
        { "room_id": "\(roomId)", "phase": "playing", "playback_state": "paused", "selection_mode": "vote",
          "selection_revision": \(selectionRevision), "selected_content_id": "movie:1",
          "selected_file_id": \(fileId), "selected_library_id": 3, "code": "ABCD",
          "guest_control_policy": "guest_play_pause", "is_paused": true, "anchor_position_seconds": \(anchor),
          "anchor_updated_at": "2026-01-01T00:00:00Z", "generation": \(generation), "member_count": 2,
          "host_connected": true, "self_role": "host", "self_can_control_transport": true,
          "self_can_manage_room": true, "self_ignore_wait": false, "attached_session_id": "s1",
          "invite_path": "/watch/ABCD",
          "members": [
            { "user_id": 7, "profile_id": "p1", "display_name": "Ada", "is_host": true, "is_self": true,
              "connected": true, "is_ready": true, "lobby_ready": true },
            { "user_id": "u-8", "profile_id": "p2", "display_name": "Grace", "is_host": false,
              "is_self": false, "connected": false } ] }
        """
    }

    func testEnumsKeepUnknownValues() throws {
        XCTAssertEqual(try decode([WatchPartyPhase].self, #"["lobby","playing","ended","paused"]"#),
                       [.lobby, .playing, .ended, .unknown("paused")])
        XCTAssertEqual(try decode([WatchPartyPlaybackState].self, #"["idle","waiting","paused","playing","seeking"]"#),
                       [.idle, .waiting, .paused, .playing, .unknown("seeking")])
        XCTAssertEqual(try decode([WatchPartySelectionMode].self, #"["host_pick","vote","random"]"#),
                       [.hostPick, .vote, .unknown("random")])
        XCTAssertEqual(try decode([WatchPartyGuestControlPolicy].self, #"["host_only","guest_play_pause","all"]"#),
                       [.hostOnly, .guestPlayPause, .unknown("all")])
        XCTAssertEqual(try decode([WatchPartyMemberRole].self, #"["host","guest","cohost"]"#),
                       [.host, .guest, .unknown("cohost")])
        XCTAssertEqual(try decode([WatchPartyTransportAction].self, #"["play","pause","seek","rewind"]"#),
                       [.play, .pause, .seek, .unknown("rewind")])
        let encoded = try JSONEncoder().encode([WatchPartyPhase.ended, .unknown("x")])
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #"["ended","x"]"#)
        XCTAssertEqual(WatchPartySourceFallbackReason(rawValue: "hdr_transcode_unsupported"), .hdrTranscodeUnsupported)
    }

    func testCapabilitiesDefaultMissingFlagsAndGateTheSocket() throws {
        let minimal = try decode(WatchPartyCapabilities.self, #"{ "state": "available", "allowed": true }"#)
        XCTAssertTrue(minimal.isAvailable)
        XCTAssertFalse(minimal.supportsSocket)
        XCTAssertFalse(minimal.picker)
        XCTAssertEqual(minimal.maxMemberStateIds, 0)

        let full = try decode(WatchPartyCapabilities.self, """
        { "revision": "7", "state": "available", "allowed": true, "staged_selection": true, "lobby_ready": true,
          "connection_replaced": true, "selection_mode_switch": true, "member_state": true, "picker": true,
          "vote_host_override": true, "stop_playback": true, "max_member_state_ids": 50,
          "socket_protocol": "prairie.room.v2" }
        """)
        XCTAssertTrue(full.supportsSocket)
        XCTAssertEqual(full.revision, "7")
        XCTAssertTrue(full.stopPlayback)
        XCTAssertEqual(full.maxMemberStateIds, 50)
        XCTAssertFalse(try decode(WatchPartyCapabilities.self, #"{ "state": "available" }"#).isAvailable)
        XCTAssertFalse(try decode(WatchPartyCapabilities.self, #"{ "state": "disabled", "allowed": true }"#).isAvailable)
        XCTAssertFalse(WatchPartyCapabilities().isAvailable)
    }

    func testRoomDecodesAndRejectsAnInvalidTimeline() throws {
        let room = try decode(WatchPartyRoom.self, roomJSON())
        XCTAssertEqual(room.id, "room-1")
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.selectedFileId, "42")
        XCTAssertEqual(room.selectedLibraryId, "3", "numeric ids become strings")
        XCTAssertEqual(room.selfRole, .host)
        XCTAssertEqual(room.guestControlPolicy, .guestPlayPause)
        XCTAssertEqual(room.members.map(\.id), ["7:p1", "u-8:p2"])
        XCTAssertTrue(room.members[0].isReady)
        XCTAssertFalse(room.members[1].isBuffering)
        XCTAssertEqual(try decode(WatchPartyRoom.self, roomJSON(fileId: "null")).selectedFileId, nil)

        for bad in [roomJSON(roomId: ""), roomJSON(selectionRevision: -1), roomJSON(generation: -1),
                    roomJSON(anchor: "-3")] {
            XCTAssertThrowsError(try decode(WatchPartyRoom.self, bad))
        }
        XCTAssertFalse(WatchPartyRoom(roomId: "r").isPlaying)

        let response = try decode(WatchPartyRoomResponse.self, #"{ "room": \#(roomJSON()), "room_access_token": "t" }"#)
        XCTAssertEqual(response.roomAccessToken, "t")
        let roundTrip = try JSONDecoder().decode(WatchPartyRoom.self, from: JSONEncoder().encode(room))
        XCTAssertEqual(roundTrip.roomId, room.roomId)
    }

    func testSuggestionsCommandsAndReceipts() throws {
        let page = try decode(WatchPartySuggestionPage.self, """
        { "items": [ { "id": "sg1", "room_id": "room-1", "suggester_user_id": 9, "suggester_profile_id": "p1",
                       "content_id": "movie:2", "content_type": "movie", "title": "Ronin",
                       "poster_url": null, "vote_count": 3, "voted_by_me": true,
                       "created_at": "2026-01-01T00:00:00Z" } ],
          "page": { "has_more": false } }
        """)
        let suggestion = try XCTUnwrap(page.items.first)
        XCTAssertEqual(suggestion.suggesterUserId, "9")
        XCTAssertEqual(suggestion.posterUrl, "")
        XCTAssertEqual(suggestion.subtitle, "")
        XCTAssertEqual(suggestion.voteCount, 3)

        let command = try decode(WatchPartyTransportCommand.self, """
        { "command_id": "c1", "selection_revision": 2, "action": "seek", "position_seconds": 30,
          "execute_at": "2026-01-01T00:00:01Z", "issued_at": "2026-01-01T00:00:00Z", "playback_state": "playing" }
        """)
        XCTAssertEqual(command.action, .seek)
        XCTAssertNil(command.sessionId)

        let fresh = WatchPartyNewSuggestion(contentId: "movie:3", contentType: "movie", title: "Heat")
        XCTAssertEqual(fresh.suggestionId, fresh.suggestionId.lowercased())
        XCTAssertFalse(fresh.suggestionId.isEmpty)
        XCTAssertEqual(try decode(WatchPartySuggestionReceipt.self, #"{ "suggestion_id": "sg2" }"#).suggestionId, "sg2")
        XCTAssertEqual(WatchPartySelection(contentId: "movie:1").fileId, nil)

        let ticket = try decode(WatchPartySocketTicket.self, """
        { "ticket": "t1", "expires_in": 30, "max_connection_seconds": 3600, "protocol": "prairie.room.v2" }
        """)
        XCTAssertEqual(ticket.protocol, "prairie.room.v2")
    }

    func testMemberStateAndPickerShapes() throws {
        let state = try decode(WatchPartyMemberState.self, """
        { "members": [ { "user_id": 1, "profile_id": "p1", "display_name": "Ada", "is_host": true,
                         "is_self": true, "connected": true } ],
          "items": [ { "content_id": "movie:1",
                       "members": [ { "user_id": "1", "profile_id": "p1", "state": "in_progress",
                                      "position_seconds": 10, "duration_seconds": 100, "on_watchlist": true } ] } ] }
        """)
        XCTAssertEqual(state.items.first?.id, "movie:1")
        XCTAssertEqual(state.items.first?.members.first?.onWatchlist, true)

        let picker = try decode(WatchPartyPicker.self, """
        { "members": [],
          "continue_together": [ { "item": { "content_id": "series:1", "type": "series", "title": "Show" },
                                   "members": [ { "user_id": "1", "profile_id": "p1", "display_name": "Ada",
                                                  "position_seconds": 5 } ],
                                   "next_up": { "content_id": "episode:3", "season_number": 1, "episode_number": 3,
                                                "title": "Three", "member_count": 2 } } ],
          "watchlist_union": [] }
        """)
        let entry = try XCTUnwrap(picker.continueTogether.first)
        XCTAssertEqual(entry.id, "series:1")
        XCTAssertEqual(entry.nextUp?.episodeNumber, 3)
        XCTAssertEqual(entry.members.first?.displayName, "Ada")
        XCTAssertTrue(picker.watchlistUnion.isEmpty)
    }
}
