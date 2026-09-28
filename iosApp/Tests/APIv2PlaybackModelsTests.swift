import Foundation
import XCTest
@testable import Prairie

/// API v2 playback wire models: capability gating, the control-socket
/// handshake, sequenced progress samples and the mutation bodies that wrap
/// them, and the source projection onto the protocol v3 descriptor.
final class APIv2PlaybackModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }

    private var requiredFeatures: [String] {
        [PlaybackProtocolV3.planFeature, PlaybackProtocolV3.neutralContractFeature,
         PlaybackProtocolV3.headerAuthenticatedMediaFeature, PlaybackSequencedContract.feature]
    }

    private func capabilities(
        state: String = "available",
        allowed: Bool = true,
        versions: [Int] = [PlaybackProtocolV3.version],
        features: [String]? = nil,
        installationID: String? = "install-1"
    ) -> APIv2PlaybackCapabilities {
        let json: [String: Any?] = [
            "installation_id": installationID,
            "revision": "r1",
            "state": state,
            "allowed": allowed,
            "protocol_versions": versions,
            "features": features ?? requiredFeatures,
            "deliveries": ["hls"],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try! HTTPClient.makeJSONDecoder().decode(APIv2PlaybackCapabilities.self, from: data)
    }

    private func failureReason(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) -> String? {
        do {
            try body()
            XCTFail("expected a terminal failure", file: file, line: line)
            return nil
        } catch let failure as PlaybackV3TerminalFailure {
            XCTAssertFalse(failure.retryable, file: file, line: line)
            XCTAssertEqual(failure.errorDescription, failure.message, file: file, line: line)
            return failure.reason
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
            return nil
        }
    }

    func testCapabilitiesGateEveryUnavailableState() throws {
        XCTAssertEqual(try capabilities().requireAvailable(), "install-1")
        XCTAssertEqual(failureReason { _ = try capabilities(state: "not_configured").requireAvailable() },
                       "playback_not_configured")
        XCTAssertEqual(failureReason { _ = try capabilities(state: "unsupported").requireAvailable() },
                       "playback_unsupported")
        XCTAssertEqual(failureReason { _ = try capabilities(state: "disabled").requireAvailable() },
                       "playback_unavailable")
        XCTAssertEqual(failureReason { _ = try capabilities(allowed: false).requireAvailable() },
                       "playback_unavailable")
        XCTAssertEqual(failureReason { _ = try capabilities(versions: [2]).requireAvailable() },
                       "server_upgrade_required")
        XCTAssertEqual(failureReason {
            _ = try capabilities(features: Array(requiredFeatures.dropLast())).requireAvailable()
        }, "server_upgrade_required")
        XCTAssertEqual(failureReason { _ = try capabilities(installationID: nil).requireAvailable() },
                       "playback_not_configured")
        XCTAssertEqual(failureReason { _ = try capabilities(installationID: "").requireAvailable() },
                       "playback_not_configured")
    }

    private func ticket(
        _ ticket: String = "tk_1.2-3",
        expiresIn: Int = 60,
        maxConnectionSeconds: Int = 3600,
        protocolName: String = "prairie.playback-control.v2"
    ) throws -> APIv2PlaybackControlTicket {
        try decode(APIv2PlaybackControlTicket.self, """
        { "ticket": "\(ticket)", "expires_in": \(expiresIn),
          "max_connection_seconds": \(maxConnectionSeconds), "protocol": "\(protocolName)" }
        """)
    }

    func testControlTicketBuildsTheWebSocketHandshake() throws {
        let session = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"
        let secure = try ticket().handshake(serverURL: "https://media.example/prairie/", sessionID: session)
        XCTAssertEqual(secure.maxConnectionSeconds, 3600)
        XCTAssertEqual(secure.request.url?.absoluteString,
                       "wss://media.example/prairie/api/v2/playback/sessions/\(session)/control/ws")
        XCTAssertEqual(secure.request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"),
                       "prairie.playback-control.v2, prairie.ticket.tk_1.2-3")

        let plain = try ticket().handshake(serverURL: "http://10.0.0.5:8096", sessionID: session)
        XCTAssertEqual(plain.request.url?.absoluteString,
                       "ws://10.0.0.5:8096/api/v2/playback/sessions/\(session)/control/ws")
    }

    func testControlTicketRejectsUnsafeInputs() throws {
        let session = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"
        let rejected: [(APIv2PlaybackControlTicket, String, String)] = [
            (try ticket(protocolName: "silo.playback-control.v2"), "https://m.example", session),
            (try ticket(expiresIn: 0), "https://m.example", session),
            (try ticket(maxConnectionSeconds: 0), "https://m.example", session),
            (try ticket(maxConnectionSeconds: APIv2PlaybackControlTicket.maxAcceptedConnectionSeconds + 1),
             "https://m.example", session),
            (try ticket(""), "https://m.example", session),
            (try ticket("bad ticket"), "https://m.example", session),
            (try ticket(), "https://m.example", "not-a-uuid"),
            (try ticket(), "ftp://m.example", session),
            (try ticket(), "https://user:pw@m.example", session),
            (try ticket(), "https://m.example?x=1", session),
            (try ticket(), "https://m.example#frag", session),
            (try ticket(), "/relative/only", session),
        ]
        for (value, server, sessionID) in rejected {
            XCTAssertThrowsError(try value.handshake(serverURL: server, sessionID: sessionID), server) { error in
                guard case PlaybackSequencedError.invalidResponse = error else {
                    return XCTFail("unexpected error \(error)")
                }
            }
        }
    }

    func testControlCapabilitiesServeHandshakeOnlyWhenFullyAvailable() throws {
        func caps(available: Bool = true, proto: String = "prairie.playback-control.v2",
                  state: String = "available", allowed: Bool = true) throws -> APIv2PlaybackControlCapabilities {
            try decode(APIv2PlaybackControlCapabilities.self, """
            { "available": \(available), "protocol": "\(proto)", "revision": "1",
              "state": "\(state)", "allowed": \(allowed) }
            """)
        }
        XCTAssertTrue(try caps().servesControlHandshake)
        XCTAssertFalse(try caps(available: false).servesControlHandshake)
        XCTAssertFalse(try caps(proto: "other").servesControlHandshake)
        XCTAssertFalse(try caps(state: "disabled").servesControlHandshake)
        XCTAssertFalse(try caps(allowed: false).servesControlHandshake)
    }

    func testSequencedSamplesValidateAndEncodeIntoMutationBodies() throws {
        XCTAssertThrowsError(try PlaybackSequencedSample(sequence: 0, position: 1, isPaused: false))
        XCTAssertThrowsError(try PlaybackSequencedSample(sequence: 1, position: -1, isPaused: false))
        XCTAssertThrowsError(try PlaybackSequencedSample(sequence: 1, position: .infinity, isPaused: false))
        // The sample spells its snake_case keys out, so read it with a
        // coder that does not convert keys.
        let plain = JSONDecoder()
        XCTAssertThrowsError(try plain.decode(PlaybackSequencedSample.self,
                                              from: Data(#"{ "sequence": 0, "position": 1, "is_paused": false }"#.utf8)))

        let sample = try PlaybackSequencedSample(sequence: 7, position: 12.5, isPaused: true)
        XCTAssertEqual(try plain.decode(PlaybackSequencedSample.self,
                                        from: Data(#"{ "sequence": 7, "position": 12.5, "is_paused": true }"#.utf8)), sample)
        XCTAssertEqual(try plain.decode(PlaybackSequencedSample.self, from: JSONEncoder().encode(sample)), sample)

        let progress = try object(APIv2PlaybackProgressBody(installationID: "i1", sample: sample))
        XCTAssertEqual(progress["installation_id"] as? String, "i1")
        XCTAssertEqual(progress["sequence"] as? Int, 7)
        XCTAssertEqual(progress["position"] as? Double, 12.5)
        XCTAssertEqual(progress["is_paused"] as? Bool, true)

        let stop = try object(APIv2PlaybackStopBody(installationID: "i1", stopID: "s1", finalSample: sample))
        XCTAssertEqual(stop["stop_id"] as? String, "s1")
        XCTAssertEqual(stop["sequence"] as? Int, 7)
        let bareStop = try object(APIv2PlaybackStopBody(installationID: "i1", stopID: "s2", finalSample: nil))
        XCTAssertEqual(Set(bareStop.keys), ["installation_id", "stop_id"])

        var sequence = PlaybackProgressSequence()
        XCTAssertEqual(sequence.next(for: "a"), 1)
        XCTAssertEqual(sequence.next(for: "a"), 2)
        XCTAssertEqual(sequence.next(for: "b"), 1)
        sequence.forget("a")
        XCTAssertEqual(sequence.next(for: "a"), 1)

        for error in [PlaybackSequencedError.invalidSample, .invalidResponse, .invalidSession,
                      .authorityChanged, .pendingStart, .controlUnavailable] {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    func testMutationReceiptsDecode() throws {
        let applied = try decode(APIv2PlaybackMutation.self, """
        { "outcome": "applied", "accepted": { "sequence": 3, "position": 9.5, "is_paused": false } }
        """)
        XCTAssertEqual(applied.outcome, APIv2PlaybackMutation.Outcome.applied)
        XCTAssertEqual(applied.accepted?.sequence, 3)
        XCTAssertNil(applied.stopId)

        let stopped = try decode(APIv2PlaybackMutation.self, """
        { "outcome": "stopped", "stop_id": "s1", "history_id": "h1" }
        """)
        XCTAssertEqual(stopped.outcome, APIv2PlaybackMutation.Outcome.stopped)
        XCTAssertEqual(stopped.historyId, "h1")
        XCTAssertNil(stopped.accepted)
        XCTAssertEqual(APIv2PlaybackMutation.Outcome.replayed, "replayed")
        XCTAssertEqual(APIv2PlaybackMutation.Outcome.staleSample, "stale_sample")

        let receipt = try decode(APIv2PlaybackRouteEventReceipt.self, #"{ "event_id": "e1", "outcome": "recorded" }"#)
        XCTAssertEqual(receipt.eventId, "e1")
    }

    private let sourceJSON = #"""
    { "media_file_id": "42", "duration_seconds": 60, "container": "mkv", "video_codec": "hevc",
      "video_profile": "main10", "video_level": 150, "bit_depth": 10, "color_range": "tv",
      "width": 3840, "height": 2160, "frame_rate": 23.976, "bitrate_kbps": 20000,
      "dynamic_range": "dolby_vision", "hdr10_plus": false, "dolby_vision_profile": 8,
      "dv_bl_compat_id": 1, "dv_enhancement_layer": "none", "audio_codec": "eac3",
      "audio_channels": 6, "audio_layout": "5.1", "video_copy_unsafe": false }
    """#

    func testSourceProjectsOntoTheProtocolV3Descriptor() throws {
        let source = try decode(APIv2PlaybackSource.self, sourceJSON).legacy()
        XCTAssertEqual(source.mediaFileId, 42)
        XCTAssertEqual(source.durationSeconds, 60)
        XCTAssertEqual(source.videoCodec, "hevc")
        XCTAssertEqual(source.videoLevel, 150)
        XCTAssertEqual(source.width, 3840)
        XCTAssertEqual(source.frameRate, 23.976)
        XCTAssertEqual(source.dolbyVisionProfile, 8)
        XCTAssertEqual(source.dvBlCompatId, 1)
        XCTAssertEqual(source.audioLayout, "5.1")
        XCTAssertEqual(source.videoCopyUnsafe, false)

        for bad in ["abc", "0", "042"] {
            let json = sourceJSON.replacingOccurrences(of: #""media_file_id": "42""#, with: #""media_file_id": "\#(bad)""#)
            XCTAssertThrowsError(try decode(APIv2PlaybackSource.self, json).legacy(), bad)
        }
    }

    func testTerminalDecisionWithoutPlanProjects() throws {
        let decision = try decode(APIv2PlaybackDecision.self, """
        { "protocol_version": 3, "server_features": ["playback_plan_v3"], "outcome": "terminal",
          "session_id": null }
        """).legacy()
        XCTAssertEqual(decision.protocolVersion, 3)
        XCTAssertEqual(decision.serverFeatures, ["playback_plan_v3"])
        XCTAssertEqual(decision.outcome, "terminal")
        XCTAssertNil(decision.playbackPlan)
    }
}
