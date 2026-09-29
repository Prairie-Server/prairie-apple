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

    func testDeviceLoginStatusRawMapping() {
        XCTAssertEqual(DeviceLoginStatus(raw: "pending"), .pending)
        XCTAssertEqual(DeviceLoginStatus(raw: "approved"), .approved)
        XCTAssertEqual(DeviceLoginStatus(raw: "nope"), .unknown)
    }

}
