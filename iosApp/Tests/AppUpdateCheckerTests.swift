import XCTest
@testable import Prairie

private final class AppUpdateURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class AppUpdateCheckerTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AppUpdateURLProtocol.self]
        session = URLSession(configuration: config)
        AppUpdateURLProtocol.handler = nil
    }

    override func tearDown() {
        AppUpdateURLProtocol.handler = nil
        session = nil
        super.tearDown()
    }

    func testParseAcceptsPrefixAndBuildMetadata() {
        XCTAssertEqual(AppVersion.parse("v1.4.0"), AppVersion(major: 1, minor: 4, patch: 0, prerelease: false))
        XCTAssertEqual(AppVersion.parse("1.4.0+2"), AppVersion(major: 1, minor: 4, patch: 0, prerelease: false))
        XCTAssertEqual(AppVersion.parse("v1.4.0-rc.1")?.prerelease, true)
        XCTAssertEqual(AppVersion.parse("1.4")?.patch, 0)
        XCTAssertEqual(AppVersion.parse("2.0.abc")?.patch, 0)
        XCTAssertNil(AppVersion.parse(nil))
        XCTAssertNil(AppVersion.parse(""))
        XCTAssertNil(AppVersion.parse("   "))
        XCTAssertNil(AppVersion.parse("1"))
        XCTAssertNil(AppVersion.parse("not-a-version"))
        XCTAssertEqual(AppVersion.parse("v1.4.0")?.displayString, "1.4.0")
    }

    func testVersionOrdering() {
        let a = AppVersion(major: 1, minor: 4, patch: 1, prerelease: false)
        let b = AppVersion(major: 1, minor: 4, patch: 0, prerelease: false)
        let pre = AppVersion(major: 1, minor: 4, patch: 0, prerelease: true)
        XCTAssertTrue(b < a)
        XCTAssertTrue(pre < b)
        XCTAssertFalse(b < b)
        XCTAssertFalse(a < b)
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
        XCTAssertEqual(status.latestVersionLabel, "1.4.0")
        XCTAssertEqual(status.releaseURL?.absoluteString, "https://example.com/r")
        XCTAssertEqual(status.changelogURL?.absoluteString, "https://example.com/r")
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
        XCTAssertNil(status.releaseURL)
        XCTAssertEqual(status.latestVersionLabel, "1.4.0")
    }

    func testResolveUnavailablePaths() {
        let badCurrent = AppUpdateResolver.resolve(
            currentVersionName: "bogus",
            latestVersionName: "1.0.0",
            releaseURL: nil
        )
        XCTAssertEqual(badCurrent.statusLabel, "Couldn't check for updates")
        XCTAssertNil(badCurrent.latestVersionLabel)
        XCTAssertNil(badCurrent.releaseURL)

        let blankLatest = AppUpdateResolver.resolve(
            currentVersionName: "1.0.0",
            latestVersionName: "   ",
            releaseURL: nil,
            changelogURL: AppUpdateChecker.defaultChangelogURL
        )
        guard case .unavailable(_, _, let url) = blankLatest else {
            return XCTFail("expected unavailable")
        }
        XCTAssertEqual(url, AppUpdateChecker.defaultChangelogURL)

        let unparsableLatest = AppUpdateResolver.resolve(
            currentVersionName: "1.0.0",
            latestVersionName: "not-a-version",
            releaseURL: nil
        )
        guard case .unavailable = unparsableLatest else {
            return XCTFail("expected unavailable")
        }
    }

    func testStatusAccessorsForChecking() {
        let status = AppUpdateStatus.checking
        XCTAssertEqual(status.statusLabel, "Checking…")
        XCTAssertNil(status.latestVersionLabel)
        XCTAssertNil(status.changelogURL)
        XCTAssertNil(status.releaseURL)
    }

    func testDisplayAndMarketingVersionStrings() {
        let marketing = AppUpdateChecker.marketingVersionString()
        XCTAssertFalse(marketing.isEmpty)
        let display = AppUpdateChecker.displayVersionString()
        XCTAssertFalse(display.isEmpty)
        XCTAssertTrue(display.contains(marketing) || display == marketing)
    }

    func testCheckReportsUpdateAvailable() async {
        AppUpdateURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Prairie-Apple")
            let body = """
            {"tag_name":"v1.4.0","html_url":"https://github.com/Prairie-Server/prairie-apple/releases/tag/v1.4.0"}
            """.data(using: .utf8)!
            return (200, body)
        }
        let status = await AppUpdateChecker.check(
            currentVersionName: "0.3.11",
            session: session,
            releasesLatestURL: URL(string: "https://example.test/latest")!
        )
        guard case .updateAvailable(_, let latest, let release, _) = status else {
            return XCTFail("expected updateAvailable, got \(status)")
        }
        XCTAssertEqual(latest, "1.4.0")
        XCTAssertEqual(release?.absoluteString, "https://github.com/Prairie-Server/prairie-apple/releases/tag/v1.4.0")
    }

    func testCheckTreats404AsUpToDate() async {
        AppUpdateURLProtocol.handler = { _ in (404, Data("{\"message\":\"Not Found\"}".utf8)) }
        let status = await AppUpdateChecker.check(
            currentVersionName: "0.3.11",
            session: session,
            releasesLatestURL: URL(string: "https://example.test/latest")!
        )
        guard case .upToDate(let current, let latest, let changelog) = status else {
            return XCTFail("expected upToDate, got \(status)")
        }
        XCTAssertEqual(current, "0.3.11")
        XCTAssertEqual(latest, "0.3.11")
        XCTAssertEqual(changelog, AppUpdateChecker.defaultChangelogURL)
    }

    func testCheckMapsHTTPErrorToUnavailable() async {
        AppUpdateURLProtocol.handler = { _ in (500, Data("boom".utf8)) }
        let status = await AppUpdateChecker.check(
            currentVersionName: "0.1.0",
            session: session,
            releasesLatestURL: URL(string: "https://example.test/latest")!
        )
        guard case .unavailable(_, let reason, let changelog) = status else {
            return XCTFail("expected unavailable, got \(status)")
        }
        XCTAssertEqual(reason, "Couldn't check for updates")
        XCTAssertEqual(changelog, AppUpdateChecker.defaultChangelogURL)
    }

    func testCheckMapsNetworkFailureToUnavailable() async {
        AppUpdateURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let status = await AppUpdateChecker.check(
            currentVersionName: "0.1.0",
            session: session,
            releasesLatestURL: URL(string: "https://example.test/latest")!
        )
        guard case .unavailable = status else {
            return XCTFail("expected unavailable, got \(status)")
        }
    }

    func testCheckUsesReleaseNameWhenTagMissing() async {
        AppUpdateURLProtocol.handler = { _ in
            let body = """
            {"name":"v0.2.0","html_url":"https://example.com/r"}
            """.data(using: .utf8)!
            return (200, body)
        }
        let status = await AppUpdateChecker.check(
            currentVersionName: "0.1.0",
            session: session,
            releasesLatestURL: URL(string: "https://example.test/latest")!
        )
        guard case .updateAvailable(_, let latest, _, _) = status else {
            return XCTFail("expected updateAvailable, got \(status)")
        }
        XCTAssertEqual(latest, "0.2.0")
    }

    func testCheckFallsBackChangelogWhenHTMLURLMissing() async {
        AppUpdateURLProtocol.handler = { _ in
            let body = Data("{\"tag_name\":\"v0.2.0\"}".utf8)
            return (200, body)
        }
        let status = await AppUpdateChecker.check(
            currentVersionName: "0.1.0",
            session: session,
            releasesLatestURL: URL(string: "https://example.test/latest")!
        )
        guard case .updateAvailable(_, _, let release, let changelog) = status else {
            return XCTFail("expected updateAvailable, got \(status)")
        }
        XCTAssertNil(release)
        XCTAssertEqual(changelog, AppUpdateChecker.defaultChangelogURL)
    }

    func testUpdateAvailableChangelogFallsBackToRelease() {
        let status = AppUpdateStatus.updateAvailable(
            current: "1.0.0",
            latest: "1.1.0",
            releaseURL: URL(string: "https://example.com/r"),
            changelogURL: nil
        )
        XCTAssertEqual(status.changelogURL?.absoluteString, "https://example.com/r")
    }
}
