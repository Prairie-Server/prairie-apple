import Foundation

@main
struct LocalHLSRequestLogPolicyTests {
    static func main() {
        testErrorsBypassStartupLogCap()
        print("LocalHLSRequestLogPolicyTests: all passed")
    }

    private static func testErrorsBypassStartupLogCap() {
        precondition(
            !LocalHLSRequestLogPolicy.shouldLog(
                status: 200,
                requestLogCount: 80,
                startupRequestLogLimit: 80,
                signatureAlreadyLogged: false
            ),
            "successful requests should still respect the startup log cap"
        )
        precondition(
            LocalHLSRequestLogPolicy.shouldLog(
                status: 410,
                requestLogCount: 80,
                startupRequestLogLimit: 80,
                signatureAlreadyLogged: false
            ),
            "HLS errors after the startup cap must remain visible"
        )
        precondition(
            !LocalHLSRequestLogPolicy.shouldLog(
                status: 410,
                requestLogCount: 80,
                startupRequestLogLimit: 80,
                signatureAlreadyLogged: true
            ),
            "duplicate HLS error signatures should still be suppressed"
        )
    }
}
