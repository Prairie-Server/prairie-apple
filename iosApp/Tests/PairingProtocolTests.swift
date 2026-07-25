import XCTest
import Foundation
@testable import Prairie

final class PairingProtocolTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func roundTrip(_ message: PairingMessage) -> PairingMessage {
        let data = try! encoder.encode(message)
        return try! decoder.decode(PairingMessage.self, from: data)
    }

    func testRoundTripsEveryCase() {
        let cases: [PairingMessage] = [
            .hello(tvName: "Living Room", tvDeviceId: "ABC-123", state: .setup, supportedVersions: [1]),
            .pushServer(serverURL: "https://media.example.com", serverName: "Home"),
            .pushServer(serverURL: "https://media.example.com", serverName: nil),
            .deviceStarted(serverURL: "https://media.example.com", userCode: "WXYZ-12", matchCode: "brave-otter"),
            .serverResult(serverURL: "https://media.example.com", status: .signedIn, error: nil),
            .serverResult(serverURL: "https://media.example.com", status: .failed, error: "timeout"),
            .done,
            .cancel(reason: "user_declined")
        ]
        for message in cases {
            XCTAssertTrue(roundTrip(message) == message, "round-trip mismatch for \(message)")
        }
    }

    func testTypeDiscriminatorAndVersionArePresent() {
        let data = try! encoder.encode(PairingMessage.done)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(json["type"] as? String == "done", "missing/incorrect type discriminator")
        XCTAssertTrue(json["v"] as? Int == PairingProtocol.version, "missing/incorrect version")
    }

    func testUnknownTypeFailsToDecode() {
        let data = #"{"type":"bogus","v":1}"#.data(using: .utf8)!
        var threw = false
        do { _ = try decoder.decode(PairingMessage.self, from: data) } catch { threw = true }
        XCTAssertTrue(threw, "decoding an unknown type should throw")
    }
}
