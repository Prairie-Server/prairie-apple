import XCTest
@testable import Silo

/// NOTE: This project has no unit-test target wired into project.yml yet, so
/// these tests are not currently compiled or executed. They document the
/// intended behavior and will run once a SiloTests target is added.
final class SiloCastTests: XCTestCase {
    private func roundTrip(_ message: SiloCastMessage) throws -> SiloCastMessage {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(SiloCastMessage.self, from: data)
    }

    func testPingPongRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.ping), .ping)
        XCTAssertEqual(try roundTrip(.pong), .pong)
    }

    func testVolumeMuteNextCommandsRoundTrip() throws {
        let setVol = SiloCastControlCommand.setVolume(0.4)
        XCTAssertEqual(try roundTrip(.control(setVol)), .control(setVol))
        let mute = SiloCastControlCommand.setMuted(true)
        XCTAssertEqual(try roundTrip(.control(mute)), .control(mute))
        XCTAssertEqual(try roundTrip(.control(.playNext)), .control(.playNext))
    }
}
