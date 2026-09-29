import Foundation
import XCTest
@testable import Prairie

/// TokenStore's fail-closed paths: rotations and invalidations that must be
/// discarded because the captured owner no longer matches, and canonical
/// session storage that cannot be read or written.
final class TokenStoreFailureTests: XCTestCase {
    /// Canonical session storage that can be made to fail on demand.
    private final class FlakySessions: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]
        var failReads = false
        var failWrites = false
        var failRemoves = false

        func put(_ value: String?, for key: String) { lock.withLock { values[key] = value } }

        var persistence: AccountSessionPersistence {
            AccountSessionPersistence(
                read: { [self] key in
                    try lock.withLock {
                        if failReads { throw AccountSessionPersistenceError.unavailable }
                        return values[key]
                    }
                },
                write: { [self] value, key in
                    lock.withLock {
                        guard !failWrites else { return false }
                        values[key] = value
                        return true
                    }
                },
                remove: { [self] key in
                    lock.withLock {
                        guard !failRemoves else { return false }
                        values[key] = nil
                        return true
                    }
                }
            )
        }
    }

    private var suiteName: String!
    private var suite: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!
    private var sessions: FlakySessions!

    private let serverA = ServerRegistry.serverId(for: "https://flaky-a.example")
    private let serverB = ServerRegistry.serverId(for: "https://flaky-b.example")

    override func setUp() {
        super.setUp()
        suiteName = "TokenStoreFailureTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        keychain = .inMemory(service: "TokenStoreFailureTests.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: suite)
        sessions = FlakySessions()
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        keychain = nil
        defaults = nil
        sessions = nil
        super.tearDown()
    }

    private func signedInStore() async throws -> TokenStore {
        let store = TokenStore(keychain: keychain, defaults: defaults, sessionPersistence: sessions.persistence)
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

    // MARK: - Canonical storage failures

    func testRotationFailsClosedWhenStorageMisbehaves() async throws {
        let store = try await signedInStore()
        let current = try await account(store)
        let captureValue = await store.captureRefreshCredential(expected: current)
        let capture = try XCTUnwrap(captureValue)

        sessions.failReads = true
        let unreadable = await store.saveRefreshedTokens("a2", "r2", replacing: capture)
        XCTAssertFalse(unreadable)
        sessions.failReads = false

        // Another writer replaced the stored record behind this actor.
        let replaced = CanonicalAccountSession(version: 1, signedOut: false, origin: "https://flaky-a.example",
            accountID: "acct", epoch: UUID(), accessToken: "other-access", refreshToken: "other-refresh")
        let original = try XCTUnwrap(sessions.persistence.read(AccountSessionPersistence.recordKey(serverA)))
        sessions.put(String(decoding: try JSONEncoder().encode(replaced), as: UTF8.self),
                     for: AccountSessionPersistence.recordKey(serverA))
        let mismatched = await store.saveRefreshedTokens("a2", "r2", replacing: capture)
        XCTAssertFalse(mismatched)
        sessions.put(original, for: AccountSessionPersistence.recordKey(serverA))

        sessions.failWrites = true
        let unwritable = await store.saveRefreshedTokens("a2", "r2", replacing: capture)
        XCTAssertFalse(unwritable)
        let blocked = await store.getAccessToken()
        XCTAssertNil(blocked, "a rotation that cannot be saved blocks the runtime session")
    }

    func testInvalidationAndDeletionReportStorageFailures() async throws {
        let store = try await signedInStore()
        let current = try await account(store)
        let captureValue = await store.captureRefreshCredential(expected: current)
        let capture = try XCTUnwrap(captureValue)

        sessions.failWrites = true
        let invalidated = await store.invalidateRejectedRefresh(capture)
        XCTAssertNil(invalidated, "no expiry is reported while the tombstone cannot be written")
        let stillSignedIn = await store.getAccessToken()
        XCTAssertEqual(stillSignedIn, "access-1")

        sessions.failRemoves = true
        let deleted = await store.deleteTokens(for: serverB)
        XCTAssertFalse(deleted)
    }

    func testUnreadableStorageBlocksReads() async throws {
        let store = try await signedInStore()
        let expectation = await store.captureAccountInstallationExpectation()
        try await store.installAccountSessionForServer(serverID: serverA, origin: "https://flaky-a.example",
            accessToken: "access-2", refreshToken: "refresh-2", accountID: "acct", expected: expectation)
        let reinstalled = await store.getAccessToken()
        XCTAssertEqual(reinstalled, "access-2")

        let legacy = await store.accountSessionSnapshot(for: serverB)
        XCTAssertEqual(legacy, .legacy(accessToken: nil, refreshToken: nil, epoch: nil, profileToken: nil))

        sessions.failReads = true
        let other = await store.getAccessToken(for: serverB)
        XCTAssertNil(other)
        let snapshot = await store.accountSessionSnapshot(for: serverB)
        XCTAssertEqual(snapshot, .unreadable)
        let epoch = await store.getOrCreateAccountEpoch(for: serverB)
        XCTAssertNil(epoch)

        let fresh = TokenStore(keychain: keychain, defaults: defaults, sessionPersistence: sessions.persistence)
        await fresh.switchActiveServer(serverId: serverA)
        let freshAccess = await fresh.getAccessToken()
        XCTAssertNil(freshAccess, "an unreadable canonical record fails closed")
    }

    func testInstallForTheActiveServerBlocksWhenItCannotBeSaved() async throws {
        let store = try await signedInStore()
        let expectation = await store.captureAccountInstallationExpectation()
        sessions.failWrites = true
        do {
            try await store.installAccountSessionForServer(serverID: serverA, origin: "https://flaky-a.example",
                accessToken: "x", refreshToken: "y", accountID: "acct", expected: expectation)
            XCTFail("an unsaved install must throw")
        } catch {}
        let access = await store.getAccessToken()
        XCTAssertNil(access)
    }

    func testServerSwitchClearsAPushDisplayTokenIssuedForAnotherServer() async throws {
        let store = try await signedInStore()
        let profileKeychain = keychain.withAudience(.currentUser)
        XCTAssertTrue(profileKeychain.set("display-token", for: SharedStorage.applePushDisplayTokenAccount))
        defaults.set(serverA, forKey: SharedStorage.applePushDisplayTokenServerIdKey)
        await store.switchActiveServer(serverId: serverB)
        XCTAssertNil(profileKeychain.get(SharedStorage.applePushDisplayTokenAccount))
        XCTAssertNil(defaults.string(forKey: SharedStorage.applePushDisplayTokenServerIdKey))
    }
}
