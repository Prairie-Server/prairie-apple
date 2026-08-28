import XCTest
@testable import Prairie

/// Closes the last few uncovered lines in SettingValueModels for the 95% gate.
final class SettingValueModelsGateFillTests: XCTestCase {

    func testSettingJSONValueLiteralAndAccessorHelpers() throws {
        let boolVal: SettingJSONValue = true
        let intVal: SettingJSONValue = 42
        let doubleVal: SettingJSONValue = 1.5
        let stringVal: SettingJSONValue = "x"
        let arrayVal: SettingJSONValue = [1, "two"]
        let objectVal: SettingJSONValue = ["k": "v"]

        XCTAssertEqual(boolVal.boolValue, true)
        XCTAssertEqual(intVal.intValue, 42)
        XCTAssertEqual(doubleVal.doubleValue, 1.5)
        XCTAssertEqual(stringVal.stringValue, "x")
        XCTAssertEqual(arrayVal.arrayValue?.count, 2)
        XCTAssertEqual(objectVal.objectValue?["k"], .string("v"))
        XCTAssertTrue(SettingJSONValue.null.isNull)
        XCTAssertEqual(SettingJSONValue.double(2.0).intValue, 2)
        XCTAssertEqual(SettingJSONValue.int(3).doubleValue, 3.0)

        struct Box: Codable, Equatable { let name: String }
        let decoded: Box = try SettingJSONValue.object(["name": .string("Prairie")]).decoded(as: Box.self)
        XCTAssertEqual(decoded.name, "Prairie")
        XCTAssertEqual(try SettingJSONValue.encoding(Box(name: "TV")), .object(["name": .string("TV")]))
    }

    func testSettingJSONValueEncodesEveryCase() throws {
        let values: [SettingJSONValue] = [
            .null, .bool(false), .int(7), .double(1.25), .string("z"),
            .array([.int(1)]), .object(["a": .bool(true)]),
        ]
        for value in values {
            let data = try SettingsWireCoding.makeEncoder().encode(value)
            let again = try SettingsWireCoding.makeDecoder().decode(SettingJSONValue.self, from: data)
            XCTAssertEqual(value, again)
        }
    }

    func testOpenEnumAndResponseHelpers() throws {
        let scope = SettingScope.other("profile_household")
        let scopeData = try SettingsWireCoding.makeEncoder().encode(scope)
        XCTAssertEqual(
            try SettingsWireCoding.makeDecoder().decode(SettingScope.self, from: scopeData),
            scope
        )

        let kind = SettingConstraintKind.other("custom")
        let kindData = try SettingsWireCoding.makeEncoder().encode(kind)
        XCTAssertEqual(
            try SettingsWireCoding.makeDecoder().decode(SettingConstraintKind.self, from: kindData),
            kind
        )

        let response = EffectiveSettingValuesResponse(
            settings: [],
            revision: SettingKey.revision - 1
        )
        XCTAssertTrue(response.contractIsAheadOfServer)
        XCTAssertNil(response.value(for: .playbackAutoPlayNext))
        XCTAssertNil(SettingsCapabilitiesResult.serverUpgradeRequired.capabilities)
    }

    func testSettingsAPIErrorEdgeMappings() {
        XCTAssertEqual(SettingsAPIError.from(SettingsAPIError.profileRequired), .profileRequired)
        XCTAssertEqual(
            SettingsAPIError.from(
                HTTPError.http(statusCode: 404, body: #"{"error":"unknown_setting","message":"nope"}"#),
                key: "playback.foo"
            ),
            .unknownSetting(key: "playback.foo")
        )
        if case .transport = SettingsAPIError.from(NSError(domain: "test", code: 1)) {
            // expected
        } else {
            XCTFail("non-HTTP errors must map to transport")
        }
    }
}
