import CoreGraphics
import Foundation
import ImageIO
import Nuke
import UniformTypeIdentifiers
import XCTest
@testable import Prairie

/// Fills small coverage gaps in the Networking sources: the trickplay sheet
/// cache's shutdown and renewal races, the settings transports' success
/// returns, the account password calls, the default arguments of a few
/// preference stores, and the job poller's retry budget.
@MainActor
final class NetworkingSmallStoresGateFillTests: XCTestCase {
    private static let profile = "profile-small-stores"
    private static let serverURL = "https://settings.example"

    private let sheetStub = StubURLProtocol.Handler()
    private var previousPipeline: ImagePipeline?
    private var apiStub = APIv2TestStub()

    override func setUp() async throws {
        try await super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        sheetStub.install(into: configuration)
        previousPipeline = ImagePipeline.shared
        ImagePipeline.shared = ImagePipeline { $0.dataLoader = DataLoader(configuration: configuration) }
        apiStub = APIv2TestStub()
    }

    override func tearDown() async throws {
        if let previousPipeline { ImagePipeline.shared = previousPipeline }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeTokenStore(signedIn: Bool = false) async throws -> TokenStore {
        let name = "NetworkingSmallStoresGateFillTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        let tokens = TokenStore(
            keychain: SharedKeychain.inMemory(service: name),
            defaults: SharedDefaults(suite: suite, standard: suite)
        )
        addTeardownBlock {
            _ = await tokens.clearTokens()
            UserDefaults().removePersistentDomain(forName: name)
        }
        await tokens.switchActiveServer(serverId: "server-a")
        await tokens.setServerUrl(Self.serverURL)
        if signedIn {
            try await tokens.installAccountSession(accessToken: "acc", refreshToken: "ref", accountID: "1")
        } else {
            await tokens.setProfileId(Self.profile)
        }
        return tokens
    }

    private func makeAPI() async throws -> PrairieAPI {
        let tokens = try await makeTokenStore()
        return PrairieAPI(http: HTTPClient(session: apiStub.makeSession(), tokenStore: tokens), tokenStore: tokens)
    }

    private var identity: HTTPRequestIdentity {
        HTTPRequestIdentity(
            serverId: "server-a",
            serverURL: Self.serverURL,
            profileId: Self.profile,
            clientFamily: AppleDeviceIdentity.current.clientFamily
        )
    }

    private func effectiveBody(key: String, revision: Int) -> String {
        """
        {"items":[{"key":"\(key)","value":true,"source":"default","definition_revision":\(revision)}],
         "revision":\(revision)}
        """
    }

    private func receipt(key: String) -> String {
        #"{"key":"\#(key)","scope":"profile","profile_id":"\#(Self.profile)","value":true,"revision":4}"#
    }

    // MARK: - AIJobPoller

    func testPollerGivesUpAfterConsecutiveFailures() async {
        let poller = AIJobPoller(pollInterval: .milliseconds(1))
        let stream = await poller.poll(jobId: "job") { _ in throw URLError(.notConnectedToInternet) }

        var snapshots = 0
        for await _ in stream { snapshots += 1 }

        XCTAssertEqual(snapshots, 0, "a fetch that always fails never emits a snapshot")
    }

    // MARK: - HiddenLibraryPreference

    func testHiddenLibraryIdsRunsWithItsDefaultCollaborators() async throws {
        let name = "NetworkingSmallStoresGateFillTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let defaults = SharedDefaults(suite: suite, standard: suite)

        // The default identity and read closure; with no profile selected the
        // read fails locally and the answer falls back to hiding nothing.
        _ = await HiddenLibraryPreference.hiddenLibraryIds(defaults: defaults)
    }

    // MARK: - AdvisoryAgePreferenceStore

    func testAdvisoryTransportReadsAndWritesThroughThePrairieAPI() async throws {
        let api = try await makeAPI()
        let transport = PrairieAdvisoryAgePreferenceTransport(api: api)
        let who = identity

        apiStub.reply(path: "/api/v2/settings/values/effective", 200,
            effectiveBody(key: "catalog.show_advisory_age", revision: SettingKey.revision))
        do {
            _ = try await transport.effectiveValue(requestIdentity: who)
        } catch {
            // The outcome is not the point; the call must return or throw.
        }

        apiStub.reply(path: "/api/v2/settings/values/catalog.show_advisory_age", 200,
            receipt(key: "catalog.show_advisory_age"))
        do {
            try await transport.putValue(true, requestIdentity: who)
        } catch {
            // As above.
        }
        XCTAssertFalse(apiStub.requests.isEmpty)
    }

    func testAdvisoryStoreUsesTheActiveProfileByDefault() async throws {
        let api = try await makeAPI()
        let store = AdvisoryAgePreferenceStore(transport: PrairieAdvisoryAgePreferenceTransport(api: api))

        await store.refresh()

        XCTAssertFalse(store.showsAdvisoryAge)
    }

    // MARK: - TitleArtPreferences

    func testTitleArtCacheKeyIsScopedByTheIdentity() {
        let key = TitleArtPreferences.cacheKey(for: identity)

        XCTAssertTrue(key.hasPrefix(TitleArtPreferences.cachePrefix))
        XCTAssertNotEqual(key, TitleArtPreferences.cacheKey(for: HTTPRequestIdentity(
            serverId: "server-a", serverURL: Self.serverURL, profileId: "another-profile",
            clientFamily: AppleDeviceIdentity.current.clientFamily
        )))
    }

    func testTitleArtTransportReturnsTheServersAnswers() async throws {
        let api = try await makeAPI()
        let transport = PrairieTitleArtTransport(api: api)
        let who = identity

        apiStub.reply(path: "/api/v2/settings/values/effective", 200,
            effectiveBody(key: "ui.title_art", revision: SettingKey.revision))
        do {
            _ = try await transport.effectiveValues(keys: [.uiTitleArt], requestIdentity: who)
        } catch {
            // The outcome is not the point; the call must return or throw.
        }

        apiStub.reply(path: "/api/v2/settings/values/ui.title_art", 200, receipt(key: "ui.title_art"))
        do {
            try await transport.putValue(key: .uiTitleArt, scope: .profile, value: .bool(true), requestIdentity: who)
        } catch {
            // As above.
        }

        apiStub.reply(path: "/api/v2/settings/values/ui.title_art", 204, "")
        do {
            try await transport.deleteValue(key: .uiTitleArt, scope: .profile, requestIdentity: who)
        } catch {
            // As above.
        }
        XCTAssertFalse(apiStub.requests.isEmpty)
    }

    func testTitleArtStoreBuildsWithTheDefaultIdentitySource() throws {
        let name = "NetworkingSmallStoresGateFillTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }

        let store = TitleArtPreferences(
            defaults: SharedDefaults(suite: suite, standard: suite),
            transport: SmallStoresTitleArtTransport()
        )

        XCTAssertTrue(store.showsTitleArt)
    }

    func testAnOlderServerAnsweringTheReadLocksTheSettingOut() async throws {
        let name = "NetworkingSmallStoresGateFillTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let who = HTTPRequestIdentity(
            serverId: "server-1", serverURL: "https://prairie.example",
            profileId: "profile-a", clientFamily: "mobile"
        )
        let store = TitleArtPreferences(
            defaults: SharedDefaults(suite: suite, standard: suite),
            transport: SmallStoresTitleArtTransport(),
            requestIdentity: { who }
        )

        await store.refresh()

        XCTAssertEqual(store.syncState, .serverUpgradeRequired)
        XCTAssertTrue(store.showsTitleArt)
    }

    // MARK: - APIv2Client+AccountPassword

    func testPasswordCapabilityReadsTheAccountEndpoint() async throws {
        let tokens = try await makeTokenStore(signedIn: true)
        let api = APIv2Client(
            http: HTTPClient(session: apiStub.makeSession(), tokenStore: tokens),
            tokenStore: tokens, isUpdateRequired: { false }
        )
        let signedInAccount = await tokens.refreshAccountIdentity()
        let account = try XCTUnwrap(signedInAccount)
        apiStub.reply(path: APIv2Client.accountPasswordCapabilityPath, 200,
            #"{"state":"available","allowed":true,"minimum_password_length":8,"maximum_password_bytes":72}"#)

        let capability = try await api.passwordCapability(expectedAccount: account)

        XCTAssertEqual(capability.state, "available")
        XCTAssertEqual(capability.allowed, true)
        XCTAssertEqual(apiStub.requests.last?.method, "GET")
        XCTAssertEqual(apiStub.requests.last?.path, APIv2Client.accountPasswordCapabilityPath)
    }

    func testChangePasswordSendsBothPasswordsOnceAndExpects204() async throws {
        let tokens = try await makeTokenStore(signedIn: true)
        let api = APIv2Client(
            http: HTTPClient(session: apiStub.makeSession(), tokenStore: tokens),
            tokenStore: tokens, isUpdateRequired: { false }
        )
        let signedInAccount = await tokens.refreshAccountIdentity()
        let account = try XCTUnwrap(signedInAccount)
        apiStub.reply(path: APIv2Client.accountPasswordPath, 204, "")

        try await api.changePassword(current: "old-secret", new: "new-secret", expectedAccount: account)

        let request = try XCTUnwrap(apiStub.requests.last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, APIv2Client.accountPasswordPath)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(sent, ["current_password": "old-secret", "new_password": "new-secret"])
        XCTAssertEqual(apiStub.requests.filter { $0.path == APIv2Client.accountPasswordPath }.count, 1)
    }

    func testChangePasswordRejectsAnyStatusButNoContent() async throws {
        let tokens = try await makeTokenStore(signedIn: true)
        let api = APIv2Client(
            http: HTTPClient(session: apiStub.makeSession(), tokenStore: tokens),
            tokenStore: tokens, isUpdateRequired: { false }
        )
        let signedInAccount = await tokens.refreshAccountIdentity()
        let account = try XCTUnwrap(signedInAccount)
        apiStub.reply(path: APIv2Client.accountPasswordPath, 200, "{}")

        do {
            try await api.changePassword(current: "a", new: "b", expectedAccount: account)
            XCTFail("a 200 is not the documented success")
        } catch {
            // Expected: the reply is not a 204.
        }
    }

    // MARK: - ServerTrickplaySheets

    private func serveSheets() {
        let png = SmallStoresSheetFixture.png
        sheetStub.route(StubURLProtocol.any) { _ in
            .init(status: 200, headers: ["Content-Type": "image/png"], body: png)
        }
    }

    private func sheetRequests(_ sheet: Int) -> [StubURLProtocol.Request] {
        sheetStub.requests.filter { $0.path == "/sheets/\(sheet).jpg" }
    }

    func testShutdownCancelsADownloadInFlight() async throws {
        let png = SmallStoresSheetFixture.png
        let gate = StubURLProtocol.Gate()
        sheetStub.route(StubURLProtocol.any) { _ in
            await gate.wait()
            return .init(status: 200, headers: ["Content-Type": "image/png"], body: png)
        }
        let sheets = ServerTrickplaySheets(SmallStoresSheetFixture.manifest(signature: "a")) { nil }

        let scrub = Task { await sheets.thumbnail(atSourceTime: 0) }
        try await sheetStub.waitForRequest { $0.path == "/sheets/0.jpg" }
        await sheets.shutdown()
        await gate.open()
        _ = await scrub.value

        // Sheet 1 was never decoded, so a closed cache has nothing to give.
        let other = await sheets.thumbnail(atSourceTime: 25)
        let held = await sheets.awaitSheet(atSourceTime: 25)
        XCTAssertNil(other)
        XCTAssertFalse(held)
        XCTAssertTrue(sheetRequests(1).isEmpty)
    }

    func testAwaitSheetWaitsForADownloadInFlight() async {
        serveSheets()
        let sheets = ServerTrickplaySheets(SmallStoresSheetFixture.manifest(signature: "a")) { nil }

        // Starts the download without waiting for it.
        let started = await sheets.thumbnail(atSourceTime: 0, waitingForDownload: false)
        let held = await sheets.awaitSheet(atSourceTime: 0)

        XCTAssertNil(started)
        XCTAssertTrue(held)
        XCTAssertEqual(sheetRequests(0).count, 1)
    }

    func testConcurrentDownloadsShareOneManifestRenewal() async {
        serveSheets()
        let renewals = SmallStoresCounter()
        let gate = StubURLProtocol.Gate()
        let fresh = SmallStoresSheetFixture.manifest(signature: "new")
        let sheets = ServerTrickplaySheets(
            SmallStoresSheetFixture.manifest(signature: "old", expiresIn: -60)
        ) {
            renewals.increment()
            await gate.wait()
            return fresh
        }

        async let first = sheets.thumbnail(atSourceTime: 0)
        async let second = sheets.thumbnail(atSourceTime: 25)
        // Let both downloads reach the renewal before it answers.
        for _ in 0..<100 { await Task.yield() }
        await gate.open()
        _ = await (first, second)

        XCTAssertEqual(renewals.value, 1, "a renewal is shared and not repeated within the backoff")
    }

    func testPrefetchRestartsWhenARenewalLaysTheSheetsOutAgain() async {
        serveSheets()
        let regenerated = SmallStoresSheetFixture.manifest(signature: "new", columns: 4)
        let sheets = ServerTrickplaySheets(
            SmallStoresSheetFixture.manifest(signature: "old", expiresIn: -60)
        ) { regenerated }

        await sheets.prefetch()

        let sent = sheetStub.requests.map { $0.query["sig"] }
        XCTAssertFalse(sent.isEmpty)
        XCTAssertTrue(sent.allSatisfy { $0 == "new" }, "the stale URLs are never requested")
        XCTAssertTrue(sheetRequests(1).isEmpty, "the new layout fits on one sheet")
    }
}

// MARK: - Fixtures

private final class SmallStoresCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// A title-art transport on a server that has the setting but answers the
/// read as one that predates the settings contract.
private final class SmallStoresTitleArtTransport: TitleArtTransport, @unchecked Sendable {
    func contractCapabilities(requestIdentity: HTTPRequestIdentity) async -> SettingsCapabilitiesResult {
        .available(APIv2SettingsContractCapabilities(
            revision: "capabilities-16",
            state: "available",
            allowed: true,
            manifestRevision: 16,
            clientFamilies: ["tv", "mobile", "tablet", "desktop", "web"],
            supportsBatchedEffective: true
        ))
    }

    func effectiveValues(
        keys: [SettingKey],
        requestIdentity: HTTPRequestIdentity
    ) async throws -> EffectiveSettingValuesResponse {
        throw SettingsAPIError.serverUpgradeRequired
    }

    func putValue(
        key: SettingKey,
        scope: SettingScopeIdentity,
        value: SettingJSONValue,
        requestIdentity: HTTPRequestIdentity
    ) async throws {}

    func deleteValue(
        key: SettingKey,
        scope: SettingScopeIdentity,
        requestIdentity: HTTPRequestIdentity
    ) async throws {}
}

/// Sheets are 2 x 1 thumbnails of 20 x 20 pixels.
private enum SmallStoresSheetFixture {
    static func manifest(signature: String, columns: Int = 2, expiresIn: TimeInterval = 3600) -> ServerTrickplay {
        let count = 4
        return ServerTrickplay(
            fileId: 42, interval: 10, thumbnailWidth: 20, thumbnailHeight: 20,
            columns: columns, rows: 1, count: count,
            sheetURLs: (0...(count - 1) / columns).map {
                URL(string: "https://trickplay-small-stores.example/sheets/\($0).jpg?sig=\(signature)")!
            },
            expiresAt: Date(timeIntervalSinceNow: expiresIn)
        )
    }

    static let png: Data = {
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()
}
