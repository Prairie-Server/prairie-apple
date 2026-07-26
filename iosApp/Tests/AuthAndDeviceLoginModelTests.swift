//
//  AuthAndDeviceLoginModelTests.swift
//  PrairieTests
//

import XCTest
import Foundation
@testable import Prairie

final class AuthAndDeviceLoginModelTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        HTTPClient.makeJSONDecoder()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        // Match HTTPClient wire encoding (snake_case) so assertions catch mismatches.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testLoginRequestEncodeRoundTrip() throws {
        let body = LoginRequest(username: "ada", password: "pw", provider: "local")
        let dict = try encode(body)
        XCTAssertEqual(dict["username"] as? String, "ada")
        XCTAssertEqual(dict["password"] as? String, "pw")
        XCTAssertEqual(dict["provider"] as? String, "local")
    }

    func testLoginResponseDecodeWithImpersonation() throws {
        let response = try decode(LoginResponse.self, """
        {
          "access_token": "A",
          "refresh_token": "R",
          "expires_in": 3600,
          "user": {
            "id": 7,
            "username": "ada",
            "email": "ada@example",
            "role": "admin",
            "download_allowed": true,
            "impersonation": {
              "active": true,
              "impersonator_user_id": 1,
              "impersonator_username": "root"
            }
          }
        }
        """)
        XCTAssertEqual(response.accessToken, "A")
        XCTAssertEqual(response.user.id, 7)
        XCTAssertEqual(response.user.impersonation?.impersonatorUsername, "root")
    }

    func testRefreshSignupSetupBodies() throws {
        let refresh = try decode(RefreshResponse.self, """
        { "access_token": "A2", "refresh_token": "R2", "expires_in": 100 }
        """)
        XCTAssertEqual(refresh.expiresIn, 100)

        let setupDict = try encode(SetupRequest(username: "u", email: "e", password: "p"))
        XCTAssertEqual(setupDict["email"] as? String, "e")

        let signupDict = try encode(SignupRequest(
            username: "u", email: "e", password: "p", inviteCode: "INV"
        ))
        XCTAssertEqual(signupDict["invite_code"] as? String, "INV")
        XCTAssertNil(signupDict["inviteCode"])
    }

    func testDeviceLoginStartAndPoll() throws {
        let start = try decode(DeviceLoginStartResponse.self, """
        {
          "device_code": "dc",
          "user_code": "ABCD",
          "match_code": "12",
          "verification_uri": "https://ex/activate",
          "verification_uri_complete": "https://ex/activate?token=t",
          "expires_at": "2026-07-25T12:00:00Z",
          "expires_in": 600,
          "interval": 5,
          "device_name": "TV",
          "device_platform": "tvOS"
        }
        """)
        XCTAssertEqual(start.userCode, "ABCD")
        XCTAssertEqual(start.interval, 5)

        let poll = try decode(DeviceLoginPollResponse.self, """
        {
          "status": "approved",
          "poll_after": null,
          "access_token": "A",
          "refresh_token": "R",
          "expires_in": 3600,
          "user": {
            "id": 1,
            "username": "u",
            "email": "e",
            "role": "user"
          },
          "profile_id": "p1",
          "profile_token": "pt",
          "temporary": true
        }
        """)
        XCTAssertEqual(poll.status, "approved")
        XCTAssertEqual(poll.profileId, "p1")
        XCTAssertEqual(poll.temporary, true)
    }

    func testDeviceLoginStatusRawMapping() {
        XCTAssertEqual(DeviceLoginStatus(raw: "pending"), .pending)
        XCTAssertEqual(DeviceLoginStatus(raw: "approved"), .approved)
        XCTAssertEqual(DeviceLoginStatus(raw: "nope"), .unknown)
    }

    func testDeviceLookupAndCapability() throws {
        let lookup = try decode(DeviceLookupResponse.self, """
        {
          "match_code": "99",
          "device_name": "Living Room",
          "device_platform": "tvOS",
          "status": "pending",
          "client_purpose": "remote_playback",
          "temporary": true
        }
        """)
        XCTAssertEqual(lookup.matchCode, "99")
        XCTAssertEqual(lookup.clientPurpose, "remote_playback")

        let caps = try decode(DeviceLoginCapabilityResponse.self, """
        { "remote_playback_handoff": true, "protocol_versions": [1, 2] }
        """)
        XCTAssertTrue(caps.remotePlaybackHandoff)
        XCTAssertEqual(caps.protocolVersions, [1, 2])
    }

    func testDeviceApproveAndPollRequestEncode() throws {
        let approve = try encode(DeviceApproveRequest(code: "ABCD"))
        XCTAssertEqual(approve["code"] as? String, "ABCD")
        let poll = try encode(DeviceLoginPollRequest(deviceCode: "dc"))
        XCTAssertEqual(poll["device_code"] as? String, "dc")
        XCTAssertNil(poll["deviceCode"])
    }
}
