import Foundation
import XCTest
@testable import Prairie

/// TokenStore's fail-closed paths: rotations and invalidations that must be
/// discarded because the captured owner no longer matches, and snapshots of
/// servers with no session or no server at all.
final class TokenStoreFailureTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!

    private let serverA = ServerRegistry.serverId(for: "https://flaky-a.example")
    private let serverB = ServerRegistry.serverId(for: "https://flaky-b.example")

    override func setUp() {
        super.setUp()
        suiteName = "TokenStoreFailureTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        keychain = .inMemory(service: "TokenStoreFailureTests.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: suite)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        keychain = nil
        defaults = nil
        super.tearDown()
    }

    private func signedInStore() async throws -> TokenStore {
        let store = TokenStore(keychain: keychain, defaults: defaults)
        await store.switchActiveServer(serverId: serverA)
        await store.setServerUrl("https://flaky-a.example")
        try await store.installAccountSession(accessToken: "access-1", refreshToken: "refresh-1", accountID: "acct")
        return store
    }

    private func account(_ store: TokenStore) async throws -> RefreshAccountIdentity {
        let value = await store.refreshAccountIdentity()
        return try XCTUnwrap(value)
    }

    private func temporaryScope() -> TemporaryAuthScope {
        TemporaryAuthScope(serverId: "temp-server", serverURL: "https://temp.example", accessToken: "t-access",
                           refreshToken: "t-refresh", profileId: "temp-profile", profileToken: "t-proof",
                           controllerDeviceId: "controller", expiresAt: Date().addingTimeInterval(600))
    }

    // MARK: - Captured owner no longer current

    func testForeignOwnerCapturesAreDiscarded() async throws {
        let store = try await signedInStore()
        let current = try await account(store)
        let foreign = CapturedRefreshCredential(account: current, refreshToken: "refresh-1",
                                                owner: .persistentServer(serverId: serverB))
        let saved = await store.saveRefreshedTokens("a2", "r2", replacing: foreign)
        XCTAssertFalse(saved)
        let invalidated = await store.invalidateRejectedRefresh(foreign)
        XCTAssertNil(invalidated)
        let temporaryOwner = CapturedRefreshCredential(account: current, refreshToken: "refresh-1", owner: .temporary)
        let temporarySaved = await store.saveRefreshedTokens("a2", "r2", replacing: temporaryOwner)
        XCTAssertFalse(temporarySaved)
        let temporaryInvalidated = await store.invalidateRejectedRefresh(temporaryOwner)
        XCTAssertNil(temporaryInvalidated)
        let access = await store.getAccessToken()
        XCTAssertEqual(access, "access-1", "nothing was rotated or cleared")
    }

    func testTemporaryRotationAndRejectionAreOneShot() async throws {
        let store = try await signedInStore()
        await store.beginTemporaryScope(temporaryScope())
        let temporary = try await account(store)
        let captureValue = await store.captureRefreshCredential(expected: temporary)
        let capture = try XCTUnwrap(captureValue)

        let rotated = await store.saveRefreshedTokens("t-access-2", "t-refresh-2", replacing: capture)
        XCTAssertTrue(rotated)
        let stale = await store.saveRefreshedTokens("t-access-3", "t-refresh-3", replacing: capture)
        XCTAssertFalse(stale, "the capture's refresh token was already rotated")
        let staleInvalidation = await store.invalidateRejectedRefresh(capture)
        XCTAssertNil(staleInvalidation)

        let freshValue = await store.captureRefreshCredential(expected: temporary)
        let fresh = try XCTUnwrap(freshValue)
        let first = await store.invalidateRejectedRefresh(fresh)
        XCTAssertEqual(first, .temporarySessionExpired)
        let second = await store.invalidateRejectedRefresh(fresh)
        XCTAssertNil(second, "a rejection is reported once")

        let persistentEvent = SessionExpiryEvent(account: temporary, disposition: .persistentSessionCleared)
        let consumed = await store.shouldConsumeSessionExpiryEvent(persistentEvent)
        XCTAssertFalse(consumed)
    }

    // MARK: - Reinstall and snapshots

    func testReinstallReplacesTheActiveSessionAndOtherServersStayEmpty() async throws {
        let store = try await signedInStore()
        let expectation = await store.captureAccountInstallationExpectation()
        try await store.installAccountSessionForServer(serverID: serverA, origin: "https://flaky-a.example",
            accessToken: "access-2", refreshToken: "refresh-2", accountID: "acct", expected: expectation)
        let reinstalled = await store.getAccessToken()
        XCTAssertEqual(reinstalled, "access-2")

        let other = await store.accountSessionSnapshot(for: serverB)
        guard case .saved(let empty, _) = other else { return XCTFail("\(other)") }
        XCTAssertTrue(empty.accounts.isEmpty)
        let otherAccess = await store.getAccessToken(for: serverB)
        XCTAssertNil(otherAccess)

        let noServer = await store.accountSessionSnapshot(for: "")
        XCTAssertEqual(noServer, .unreadable)
    }
}
