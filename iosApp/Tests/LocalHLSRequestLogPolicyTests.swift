import XCTest
import Foundation
@testable import Silo

final class LocalHLSRequestLogPolicyTests: XCTestCase {
    func testErrorsBypassStartupLogCap() {
        XCTAssertFalse(
            LocalHLSRequestLogPolicy.shouldLog(
                status: 200,
                requestLogCount: 80,
                startupRequestLogLimit: 80,
                signatureAlreadyLogged: false
            ),
            "successful requests should still respect the startup log cap"
        )
        XCTAssertTrue(
            LocalHLSRequestLogPolicy.shouldLog(
                status: 410,
                requestLogCount: 80,
                startupRequestLogLimit: 80,
                signatureAlreadyLogged: false
            ),
            "HLS errors after the startup cap must remain visible"
        )
        XCTAssertFalse(
            LocalHLSRequestLogPolicy.shouldLog(
                status: 410,
                requestLogCount: 80,
                startupRequestLogLimit: 80,
                signatureAlreadyLogged: true
            ),
            "duplicate HLS error signatures should still be suppressed"
        )
    }
}
