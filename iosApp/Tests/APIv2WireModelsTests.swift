import Foundation
import XCTest
@testable import Prairie

/// Decoding, validation and body encoding for the smaller API v2 wire
/// models: accounts and profiles, device login, subtitle AI, downloads and
/// series monitors, requests and problem documents.
final class APIv2WireModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }

    private func wire<T: Encodable>(_ value: T) throws -> String {
        try XCTUnwrap(String(data: JSONEncoder().encode([value]), encoding: .utf8))
    }

    // MARK: - String enums, account, profile

    func testStringEnumsKeepUnknownValuesAndRoundTrip() throws {
        XCTAssertEqual(try decode([APIv2AccountRole].self, #"["admin","user","owner"]"#),
                       [.admin, .user, .unknown("owner")])
        XCTAssertEqual(try decode([APIv2ProgressStatus].self, #"["in_progress","completed","paused"]"#),
                       [.inProgress, .completed, .unknown("paused")])
        XCTAssertEqual(try decode([APIv2AvatarSource].self, #"["none","preset","upload","gif"]"#),
                       [.none, .preset, .upload, .unknown("gif")])
        XCTAssertEqual(try decode([APIv2QualityPreference].self, #"["auto","original","720p"]"#),
                       [.auto, .original, .unknown("720p")])
        XCTAssertEqual(try decode([APIv2SubtitleMode].self, #"["auto","always","off","smart"]"#),
                       [.auto, .always, .off, .unknown("smart")])
        XCTAssertEqual(try decode([APIv2PlaybackQuality].self, #"["1080p","2160p","720p"]"#),
                       [.p1080, .p2160, .unknown("720p")])

        XCTAssertEqual(try wire(APIv2AccountRole.unknown("owner")), #"["owner"]"#)
        XCTAssertEqual(try wire(APIv2ProgressStatus.inProgress), #"["in_progress"]"#)
        XCTAssertEqual(try wire(APIv2AvatarSource.upload), #"["upload"]"#)
        XCTAssertEqual(try wire(APIv2QualityPreference.original), #"["original"]"#)
        XCTAssertEqual(try wire(APIv2SubtitleMode.off), #"["off"]"#)
        XCTAssertEqual(try wire(APIv2PlaybackQuality.p2160), #"["2160p"]"#)
        for value in [APIv2AccountRole.admin, .user] { XCTAssertEqual(APIv2AccountRole(wireValue: value.wireValue), value) }
        for value in [APIv2ProgressStatus.completed, .unknown("x")] {
            XCTAssertEqual(APIv2ProgressStatus(wireValue: value.wireValue), value)
        }
        for value in [APIv2AvatarSource.none, .preset, .unknown("x")] {
            XCTAssertEqual(APIv2AvatarSource(wireValue: value.wireValue), value)
        }
        for value in [APIv2QualityPreference.auto, .unknown("x")] {
            XCTAssertEqual(APIv2QualityPreference(wireValue: value.wireValue), value)
        }
        for value in [APIv2SubtitleMode.auto, .always, .unknown("x")] {
            XCTAssertEqual(APIv2SubtitleMode(wireValue: value.wireValue), value)
        }
        for value in [APIv2PlaybackQuality.p1080, .unknown("x")] {
            XCTAssertEqual(APIv2PlaybackQuality(wireValue: value.wireValue), value)
        }
    }

    func testSystemAccountProgressAndProblemDecode() throws {
        let info = try decode(APIv2SystemInfo.self, """
        { "server_version": "1.2.3", "api_major": 2, "contract_digest": "sha256:x",
          "links": { "openapi": "/api/v2/openapi.json", "capabilities": "/api/v2/capabilities" } }
        """)
        XCTAssertEqual(info.apiMajor, 2)
        XCTAssertEqual(info.links.capabilities, "/api/v2/capabilities")
        XCTAssertTrue(try decode(APIv2SetupStatus.self, #"{ "needs_setup": true }"#).needsSetup)

        let account = try decode(APIv2Account.self, """
        { "id": "u1", "username": "ada", "email": "ada@example.com", "role": "admin",
          "permissions": ["downloads"], "download_allowed": true,
          "impersonation": { "active": true, "impersonator_user_id": "u0", "impersonator_username": "root" } }
        """)
        XCTAssertEqual(account.role, .admin)
        XCTAssertEqual(account.impersonation?.impersonatorUsername, "root")

        let progress = try decode(APIv2ProgressPage.self, """
        { "items": [{ "media_item_id": "m1", "position_seconds": 10, "duration_seconds": 100,
                      "completed": false, "updated_at": "2026-01-01T00:00:00.123Z" }],
          "page": { "has_more": true, "next_cursor": "c" } }
        """)
        XCTAssertEqual(progress.items.first?.mediaItemId, "m1")
        XCTAssertEqual(progress.page.nextCursor, "c")

        let problem = try decode(APIv2Problem.self, """
        { "type": "https://prairieserver.org/docs/api/v2/problems/validation_failed", "title": "Invalid",
          "status": 422, "detail": "Bad", "instance": "/x",
          "errors": [{ "location": "body.name", "code": "required", "detail": "Name is required" }] }
        """)
        XCTAssertEqual(problem.identifier, "validation_failed")
        XCTAssertEqual(problem.errors?.first?.location, "body.name")
        XCTAssertEqual(try decode(APIv2Problem.self, #"{ "type": "about:blank", "title": "t", "status": 500, "detail": "d" }"#)
            .identifier, "about:blank")
    }

    func testProfileProjectionAndPatchEncoding() throws {
        let profile = try decode(APIv2Profile.self, """
        { "id": "p1", "name": "Kid", "avatar": "", "avatar_url": "https://cdn.example/a.png",
          "avatar_source": "upload", "has_pin": true, "is_child": true, "is_primary": false,
          "max_content_rating": "PG", "quality_preference": "auto", "language": "en",
          "preferred_metadata_language": "fr", "subtitle_language": "es", "subtitle_mode": "always",
          "auto_skip_intro": true, "auto_skip_credits": false, "auto_skip_recap": true,
          "auto_play_next_preview": false, "show_forced_subtitles": true,
          "library_restrictions_enabled": true, "allowed_library_ids": ["1"], "max_playback_quality": "1080p",
          "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-02T00:00:00Z" }
        """)
        let user = profile.asUserProfile
        XCTAssertEqual(user.id, "p1")
        XCTAssertNil(user.avatarEmoji, "an empty avatar is no emoji")
        XCTAssertEqual(user.avatarImageUrl, "https://cdn.example/a.png")
        XCTAssertTrue(user.hasPin)
        XCTAssertEqual(user.subtitleMode, "always")
        XCTAssertEqual(user.preferredMetadataLanguage, "fr")

        var patch = APIv2ProfilePatch()
        patch.name = "New"
        patch.avatar = .set("🐯")
        patch.pin = .clear
        patch.isChild = false
        patch.maxContentRating = .set("R")
        patch.qualityPreference = .original
        patch.language = .clear
        patch.subtitleMode = .off
        patch.autoSkipIntro = true
        patch.autoSkipCredits = true
        patch.autoSkipRecap = false
        patch.autoPlayNextPreview = true
        patch.showForcedSubtitles = false
        patch.libraryRestrictionsEnabled = true
        patch.allowedLibraryIds = ["1", "2"]
        patch.maxPlaybackQuality = .set(.p2160)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "New")
        XCTAssertEqual(body["avatar"] as? String, "🐯")
        XCTAssertTrue(body["pin"] is NSNull)
        XCTAssertTrue(body["language"] is NSNull)
        XCTAssertEqual(body["max_content_rating"] as? String, "R")
        XCTAssertEqual(body["quality_preference"] as? String, "original")
        XCTAssertEqual(body["subtitle_mode"] as? String, "off")
        XCTAssertEqual(body["auto_play_next_preview"] as? Bool, true)
        XCTAssertEqual(body["allowed_library_ids"] as? [String], ["1", "2"])
        XCTAssertEqual(body["max_playback_quality"] as? String, "2160p")
        XCTAssertNil(body["subtitle_language"], "unchanged fields are omitted")
        XCTAssertNil(body["preferred_metadata_language"])

        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(APIv2ProfilePatch())) as? [String: Any])
        XCTAssertTrue(empty.isEmpty)

        var update = UpdateProfileBody()
        update.qualityPreference = "auto"
        update.subtitleLanguage = ""
        update.subtitleMode = "always"
        update.showForcedSubtitles = true
        update.preferredMetadataLanguage = "de"
        update.autoSkipIntro = true
        update.autoSkipCredits = false
        update.autoSkipRecap = true
        let mapped = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(update.asAPIv2Patch)) as? [String: Any])
        XCTAssertEqual(mapped["quality_preference"] as? String, "auto")
        XCTAssertTrue(mapped["subtitle_language"] is NSNull, "an empty language clears it")
        XCTAssertEqual(mapped["preferred_metadata_language"] as? String, "de")
        XCTAssertEqual(mapped["subtitle_mode"] as? String, "always")
        XCTAssertEqual(mapped["auto_skip_recap"] as? Bool, true)

        let create = try object(APIv2ProfileCreate(name: "Kids", avatar: "🐯", pin: nil, isChild: true,
            maxContentRating: "PG", libraryRestrictionsEnabled: false, allowedLibraryIds: []))
        XCTAssertEqual(create["name"] as? String, "Kids")
        XCTAssertEqual(create["is_child"] as? Bool, true)
        XCTAssertNil(create["pin"])
    }

    // MARK: - Device login

    private func poll(status: String, tokens: Bool, temporary: Bool = false,
                      expires: Bool = true, profile: String = "p1", token: String = "pt") throws -> APIv2DevicePoll {
        let tokenJSON = tokens ? """
        "tokens": { "access_token": "a", "refresh_token": "r", "expires_in": 3600,
          "user": { "id": "u1", "username": "ada", "email": "e", "role": "user",
                    "permissions": [], "download_allowed": false } },
        """ : ""
        return try decode(APIv2DevicePoll.self, """
        { "status": "\(status)", "poll_after": 5, \(tokenJSON)
          "profile_id": "\(profile)", "profile_token": "\(token)", "temporary": \(temporary)
          \(expires ? #", "session_expires_at": "2026-01-01T00:00:00Z""# : "") }
        """)
    }

    func testDevicePollValidation() throws {
        for status in ["pending", "denied", "expired", "consumed"] {
            XCTAssertEqual(try poll(status: status, tokens: false).validated().status, status)
            XCTAssertThrowsError(try poll(status: status, tokens: true).validated(), "\(status) must not carry tokens")
        }
        XCTAssertThrowsError(try poll(status: "mystery", tokens: false).validated())
        let approved = try poll(status: "approved", tokens: true).validated()
        XCTAssertEqual(approved.tokens?.user.id, "u1")
        XCTAssertEqual(approved.tokens?.expiresIn, 3600)
        XCTAssertThrowsError(try poll(status: "approved", tokens: false).validated())
        XCTAssertNoThrow(try poll(status: "approved", tokens: true, temporary: true).validated())
        XCTAssertThrowsError(try poll(status: "approved", tokens: true, temporary: true, expires: false).validated())
        XCTAssertThrowsError(try poll(status: "approved", tokens: true, temporary: true, profile: "").validated())
        XCTAssertThrowsError(try poll(status: "approved", tokens: true, temporary: true, token: "").validated())
    }

    func testDeviceCapabilityStartAndLookup() throws {
        func capability(state: String = "available", handoff: Bool = true, versions: String = "[1, 2]",
                        allowed: String = "true") throws -> APIv2DeviceCapability {
            try decode(APIv2DeviceCapability.self, """
            { "revision": "1", "state": "\(state)", "remote_playback_handoff": \(handoff),
              "protocol_versions": \(versions), "allowed": \(allowed) }
            """)
        }
        XCTAssertTrue(try capability().offersRemotePlaybackHandoff(protocolVersion: 2))
        XCTAssertTrue(try capability(allowed: "null").offersRemotePlaybackHandoff(protocolVersion: 1))
        XCTAssertFalse(try capability(allowed: "false").offersRemotePlaybackHandoff(protocolVersion: 2))
        XCTAssertFalse(try capability(state: "disabled").offersRemotePlaybackHandoff(protocolVersion: 2))
        XCTAssertFalse(try capability(handoff: false).offersRemotePlaybackHandoff(protocolVersion: 2))
        XCTAssertFalse(try capability(versions: "[1]").offersRemotePlaybackHandoff(protocolVersion: 2))
        XCTAssertEqual(try decode(APIv2DeviceDecision.self, #"{ "status": "approved" }"#).status, "approved")

        let start = try decode(APIv2DeviceStart.self, """
        { "device_code": "dc", "user_code": "ABCD", "match_code": "12", "verification_uri": "https://x/pair",
          "verification_uri_complete": "https://x/pair?c=ABCD", "expires_at": "2026-01-01T00:10:00Z",
          "expires_in": 600, "interval": 5, "device_name": "Apple TV", "device_platform": "tvOS",
          "client_purpose": "sign_in", "temporary": false }
        """).presentation
        XCTAssertEqual(start.userCode, "ABCD")
        XCTAssertEqual(start.interval, 5)
        XCTAssertEqual(start.clientPurpose, "sign_in")
        XCTAssertEqual(start.temporary, false)

        let lookup = try decode(APIv2DeviceLookup.self, """
        { "status": "pending", "user_code": "ABCD", "match_code": "12", "device_name": "Living Room",
          "device_platform": "tvOS", "ip_address_hint": "10.0.0.x", "client_purpose": "pair", "temporary": true }
        """).presentation
        XCTAssertEqual(lookup.matchCode, "12")
        XCTAssertEqual(lookup.deviceName, "Living Room")
        XCTAssertEqual(lookup.status, "pending")
        XCTAssertEqual(lookup.clientPurpose, "pair")
        XCTAssertEqual(lookup.temporary, true)
    }

    // MARK: - Subtitle AI

    private func job(id: String = "j1", kind: String = "translate", file: String = "12",
                     result: String? = "sub-1") throws -> APIv2SubtitleJob {
        let resultJSON = result.map { #""\#($0)""# } ?? "null"
        return try decode(APIv2SubtitleJob.self, """
        { "id": "\(id)", "media_file_id": "\(file)", "kind": "\(kind)", "source_index": 2,
          "source_language": "en", "target_language": "fr", "engine": "llm", "model": "m",
          "status": "running", "progress": 0.5, "progress_message": "Halfway",
          "result_subtitle_id": \(resultJSON), "error_message": null,
          "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:01:00Z" }
        """)
    }

    func testSubtitleAIStatusQuotaAndJobs() throws {
        func status(enabled: Bool = true, transcribe: Bool = true, state: String = "available",
                    allowed: Bool = true) throws -> SubtitleAIStatus {
            try decode(APIv2SubtitleAIStatus.self, """
            { "enabled": \(enabled), "transcribe_enabled": \(transcribe), "revision": "1",
              "state": "\(state)", "allowed": \(allowed) }
            """).playerValue
        }
        XCTAssertEqual(try status(), SubtitleAIStatus(enabled: true, transcribeEnabled: true))
        XCTAssertEqual(try status(transcribe: false), SubtitleAIStatus(enabled: true, transcribeEnabled: false))
        XCTAssertEqual(try status(state: "disabled"), SubtitleAIStatus(enabled: false, transcribeEnabled: false))
        XCTAssertEqual(try status(allowed: false), SubtitleAIStatus(enabled: false, transcribeEnabled: false))

        let quota = try decode(APIv2SubtitleAIQuota.self, """
        { "limited": true, "limit": 10, "used": 3, "remaining": 7, "period": "month" }
        """).playerValue
        XCTAssertEqual(quota, SubtitleAIQuota(limited: true, limit: 10, used: 3, remaining: 7, period: "month"))

        let envelope = try decode(APIv2SubtitleJobEnvelope.self, #"{ "job": \#(jobJSON()) }"#)
        let projected = try SubtitleJob(v2: envelope.job, expectedJobID: "j1")
        XCTAssertEqual(projected.mediaFileId, 12)
        XCTAssertEqual(projected.kind, .translate)
        XCTAssertEqual(projected.status, .running)
        XCTAssertEqual(projected.resultSubtitleId, "sub-1")
        XCTAssertEqual(try SubtitleJob(v2: job(kind: "transcribe_translate", result: nil), expectedJobID: "j1").kind,
                       .transcribeTranslate)

        for bad in [try job(id: "other"), try job(kind: "summarize"), try job(file: "0"),
                    try job(file: "x12"), try job(file: "012"), try job(result: "")] {
            XCTAssertThrowsError(try SubtitleJob(v2: bad, expectedJobID: "j1"))
        }

        let created = try decode(APIv2SubtitleCreateResponse.self,
                                 #"{ "job": \#(jobJSON()), "live_delivery_attached": true }"#)
        XCTAssertTrue(created.liveDeliveryAttached)
        let result = SubtitleCreationResult(job: projected, liveDeliveryAttached: created.liveDeliveryAttached)
        XCTAssertTrue(result.liveDeliveryAttached)
    }

    private func jobJSON() -> String {
        """
        { "id": "j1", "media_file_id": "12", "kind": "translate", "source_index": 2,
          "source_language": "en", "target_language": "fr", "engine": "llm", "model": "m",
          "status": "running", "progress": 0.5, "progress_message": "Halfway",
          "result_subtitle_id": "sub-1", "error_message": null,
          "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:01:00Z" }
        """
    }

    func testSubtitleCreateBodyValidation() throws {
        func body(file: Int = 12, kind: SubtitleAIKind? = .translate, index: Int = 0,
                  position: Double? = 5) -> TranslateSubtitleBody {
            TranslateSubtitleBody(mediaFileId: file, kind: kind, sourceIndex: index, sourceLanguage: nil,
                                  targetLanguage: "fr", sessionId: "s1", startPosition: position)
        }
        let encoded = try object(APIv2SubtitleCreateBody(body()))
        XCTAssertEqual(encoded["media_file_id"] as? String, "12")
        XCTAssertEqual(encoded["kind"] as? String, "translate")
        XCTAssertEqual(encoded["source_language"] as? String, "")
        XCTAssertEqual(encoded["target_language"] as? String, "fr")
        XCTAssertEqual(encoded["session_id"] as? String, "s1")
        XCTAssertNoThrow(try APIv2SubtitleCreateBody(body(index: -1, position: 0)))
        for bad in [body(file: 0), body(kind: nil), body(index: -2), body(position: nil),
                    body(position: -1), body(position: .nan)] {
            XCTAssertThrowsError(try APIv2SubtitleCreateBody(bad))
        }

        XCTAssertFalse((SubtitleCreationError.unresolved.errorDescription ?? "").isEmpty)
        XCTAssertFalse((SubtitleCreationError.outcomeUnknown.errorDescription ?? "").isEmpty)
        XCTAssertTrue(SubtitleCreationError.isUncertain(SubtitleCreationError.outcomeUnknown))
        XCTAssertFalse(SubtitleCreationError.isUncertain(HTTPError.http(statusCode: 500, body: nil)))
    }

    // MARK: - Downloads, monitors, requests

    private let entryJSON = #"""
    { "id": "d1", "content_id": "movie:1", "episode_id": null, "batch_id": "b1", "device_id": "dev",
      "media_file_id": "42", "file_size": 1000, "bytes_sent": 500, "kind": "movie",
      "status": "downloading", "quality": "original", "effective_quality": "original",
      "delivery_format": "file", "target_bitrate_kbps": 0, "revision": 2,
      "created_at": "2026-01-01T00:00:00Z", "completed_at": null, "status_event_at": "2026-01-01T00:05:00Z" }
    """#

    private let caps = DownloadCaps(clientFeatures: ["f"], videoEvidence: "platform_attested",
        codecsVideo: ["hevc"], codecsAudio: ["aac"], audioPassthroughCodecs: nil, containers: ["mp4"],
        maxResolution: "1080p", hdr: false, videoDecode: [])

    func testDownloadRegistryModels() throws {
        let capability = try decode(APIv2DownloadCapability.self, """
        { "state": "available", "allowed": true, "enabled": true, "download_allowed": true,
          "quality_presets": ["original", "10mbps"], "transcode_enabled": true,
          "transcode_user_allowed": false, "season_download": true, "series_monitoring": true,
          "monitoring_modes": ["all", "unwatched"] }
        """)
        XCTAssertEqual(capability.qualityPresets, ["original", "10mbps"])
        XCTAssertFalse(capability.transcodeUserAllowed)

        let entry = try decode(APIv2DownloadEntry.self, entryJSON)
        XCTAssertTrue(entry.isUsable)
        XCTAssertEqual(entry.bytesSent, 500)
        XCTAssertNotNil(entry.statusEventAt)
        XCTAssertFalse(try decode(APIv2DownloadEntry.self,
                                  entryJSON.replacingOccurrences(of: #""revision": 2"#, with: #""revision": 0"#)).isUsable)
        XCTAssertFalse(try decode(APIv2DownloadEntry.self,
                                  entryJSON.replacingOccurrences(of: #""media_file_id": "42""#, with: #""media_file_id": """#)).isUsable)

        let created = try decode(APIv2DownloadCreated.self, """
        { "items": [\(entryJSON)], "skipped": [{ "episode_id": "e2", "reason": "unavailable" }],
          "page": { "has_more": false }, "batch_id": "b1" }
        """)
        XCTAssertEqual(created.skipped.first?.reason, "unavailable")
        XCTAssertEqual(created.batchId, "b1")
        XCTAssertEqual(try decode(APIv2DownloadEntryPage.self, #"{ "items": [] }"#).items.count, 0)

        let fresh = APIv2DownloadCreateRequest.single(contentId: "movie:1", episodeId: nil, mediaFileId: "42",
                                                      quality: "original", caps: caps, expected: .absent)
        let freshBody = try object(fresh)
        XCTAssertEqual(freshBody["content_id"] as? String, "movie:1")
        XCTAssertEqual(freshBody["media_file_id"] as? String, "42")
        XCTAssertEqual(freshBody["expected_revision"] as? Int, 0)
        XCTAssertNil(freshBody["expected_download_id"])
        XCTAssertNil(freshBody["episode_id"])
        XCTAssertNotNil(freshBody["caps"])
        XCTAssertNil(fresh.batchId)
        XCTAssertTrue(fresh.isValid)

        let replace = APIv2DownloadCreateRequest.single(contentId: "series:1", episodeId: "e1", mediaFileId: nil,
            quality: "10mbps", caps: caps, expected: .entry(id: "d1", revision: 3))
        let replaceBody = try object(replace)
        XCTAssertEqual(replaceBody["expected_revision"] as? Int, 3)
        XCTAssertEqual(replaceBody["expected_download_id"] as? String, "d1")
        XCTAssertEqual(replaceBody["episode_id"] as? String, "e1")
        XCTAssertTrue(replace.isValid)

        let series = APIv2DownloadCreateRequest.seriesPage(seriesId: "series:1", seasonNumber: 2,
                                                           batchId: "b2", caps: caps)
        let seriesBody = try object(series)
        XCTAssertEqual(seriesBody["series"] as? Bool, true)
        XCTAssertEqual(seriesBody["season_number"] as? Int, 2)
        XCTAssertEqual(seriesBody["quality"] as? String, DownloadFormat.original.rawValue)
        XCTAssertEqual(seriesBody["batch_id"] as? String, "b2")
        XCTAssertEqual(series.batchId, "b2")
        XCTAssertTrue(series.isValid)

        let invalid: [APIv2DownloadCreateRequest] = [
            .single(contentId: "", episodeId: nil, mediaFileId: nil, quality: "q", caps: caps, expected: .absent),
            .single(contentId: "c", episodeId: nil, mediaFileId: "", quality: "q", caps: caps, expected: .absent),
            .single(contentId: "c", episodeId: nil, mediaFileId: nil, quality: "q", caps: caps,
                    expected: .entry(id: "", revision: 1)),
            .single(contentId: "c", episodeId: nil, mediaFileId: nil, quality: "q", caps: caps,
                    expected: .entry(id: "d", revision: 0)),
            .seriesPage(seriesId: "", seasonNumber: nil, batchId: "b", caps: caps),
            .seriesPage(seriesId: "s", seasonNumber: nil, batchId: "", caps: caps),
        ]
        XCTAssertTrue(invalid.allSatisfy { !$0.isValid })

        let event = DownloadStatusEvent(status: .completed, updatedAt: Date(timeIntervalSince1970: 1_700_000_000.5),
                                        revision: 4)
        let status = try object(APIv2DownloadStatusBody(event: event))
        XCTAssertEqual(status["status"] as? String, "completed")
        XCTAssertEqual(status["revision"] as? Int, 4)
        XCTAssertEqual(status["updated_at"] as? String, "2023-11-14T22:13:20.500Z")

        for error in [DownloadRegistryError.invalidRequest, .incompleteRegistry, .unexpectedReceipt, .unusableManifest] {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
        XCTAssertNotEqual(DownloadRegistryFailure.conflict, .uncertain)
    }

    func testSeriesMonitorAndRequestsModels() throws {
        let subscription = #"""
        { "id": "sub1", "series_id": "series:1", "mode": "all", "target_season": null, "season_numbers": [1],
          "delete_watched": false, "max_storage_bytes": 0, "active": true,
          "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z", "etag": "e1" }
        """#
        let page = try decode(APIv2DownloadSubscriptionPage.self, #"{ "items": [\#(subscription)] }"#)
        XCTAssertEqual(page.items.first?.etag, "e1")
        XCTAssertNil(page.page)

        let sync = try object(APIv2DownloadSubscriptionSyncBody(subscriptionId: "sub1", etag: "e1"))
        XCTAssertEqual(sync["subscription_id"] as? String, "sub1")
        XCTAssertEqual(sync["etag"] as? String, "e1")
        let receipt = try decode(APIv2DownloadSubscriptionSync.self, """
        { "subscription_id": "sub1", "registered": 2, "examined": 5, "page": { "has_more": false } }
        """)
        XCTAssertEqual(receipt.registered, 2)
        XCTAssertEqual(receipt.examined, 5)
        let outcome = DownloadSubscriptionSyncOutcome(registered: 2, reloaded: page.items.first, removed: false)
        XCTAssertEqual(outcome.reloaded?.id, "sub1")

        for error in [DownloadSubscriptionError.invalidRequest, .incompleteList, .unexpectedReceipt, .incompleteSync] {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
        for error in [APIv2RequestsError.unsupportedMediaType, .emptySearchQuery, .outcomeUnknownOwnerChanged] {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
        XCTAssertEqual(try decode(APIv2RequestsPage.self, #"{ "items": [] }"#).items.count, 0)
        XCTAssertEqual(try decode(APIv2DiscoverSectionCollection.self, #"{ "items": [] }"#).items.count, 0)
    }
}
