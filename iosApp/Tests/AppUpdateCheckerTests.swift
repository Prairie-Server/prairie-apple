import XCTest
@testable import Prairie

final class AppUpdateCheckerTests: XCTestCase {
    func testParseAcceptsPrefixAndBuildMetadata() {
        XCTAssertEqual(AppVersion.parse("v1.4.0"), AppVersion(major: 1, minor: 4, patch: 0, prerelease: false))
        XCTAssertEqual(AppVersion.parse("1.4.0+2"), AppVersion(major: 1, minor: 4, patch: 0, prerelease: false))
        XCTAssertEqual(AppVersion.parse("v1.4.0-rc.1")?.prerelease, true)
    }

    func testResolveUpdateAvailable() {
        let status = AppUpdateResolver.resolve(
            currentVersionName: "0.3.11",
            latestVersionName: "v1.4.0",
            releaseURL: URL(string: "https://example.com/r")
        )
        guard case .updateAvailable(_, let latest, let release, let changelog) = status else {
            return XCTFail("expected updateAvailable")
        }
        XCTAssertEqual(latest, "1.4.0")
        XCTAssertEqual(release?.absoluteString, "https://example.com/r")
        XCTAssertEqual(changelog?.absoluteString, "https://example.com/r")
        XCTAssertEqual(status.statusLabel, "Update available")
    }

    func testResolveUpToDateKeepsChangelog() {
        let status = AppUpdateResolver.resolve(
            currentVersionName: "1.4.0",
            latestVersionName: "v1.4.0",
            releaseURL: URL(string: "https://example.com/r"),
            changelogURL: URL(string: "https://example.com/changelog")
        )
        guard case .upToDate = status else {
            return XCTFail("expected upToDate")
        }
        XCTAssertEqual(status.statusLabel, "Up to date")
        XCTAssertEqual(status.changelogURL?.absoluteString, "https://example.com/changelog")
    }
}
