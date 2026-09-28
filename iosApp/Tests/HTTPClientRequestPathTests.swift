import Foundation
import XCTest
@testable import Prairie

/// `HTTPClient` asserts in DEBUG builds that every Prairie server request is a
/// `/api/v2` operation or the retained health probe. These cases pin the
/// predicate behind that assertion.
final class HTTPClientRequestPathTests: XCTestCase {
    func testAcceptsV2OperationsAndTheHealthProbe() {
        for path in [
            "/api/v2/account/me",
            "api/v2/catalog/items/abc",
            "/api/v2",
            HTTPClient.refreshPath,
            ConnectionMonitor.healthPath,
        ] {
            XCTAssertTrue(HTTPClient.isPrairieServerPath(path), path)
        }
    }

    func testRejectsEveryOtherServerRoute() {
        for path in [
            "/api/v1/items/abc",
            "/api/v1/health/extra",
            "/api/v2x/items",
            "/api/v3/items",
            "/health",
            "/resource",
            "",
        ] {
            XCTAssertFalse(HTTPClient.isPrairieServerPath(path), path)
        }
    }

    /// The route is checked before the server URL's base path is prepended,
    /// so a server mounted under a prefix still sends v2 requests.
    func testServerBasePathIsNotPartOfTheCheckedRoute() async throws {
        let stub = APIv2TestStub(fallback: .json(200, #"{"status":"ok"}"#))
        let _: HealthStatus = try await HTTPClient(session: stub.makeSession())
            .getUnauthenticated(serverURL: "https://example.test/prairie", path: "/api/v2/system/info")
        XCTAssertEqual(stub.requestedPaths, ["/prairie/api/v2/system/info"])
    }
}
