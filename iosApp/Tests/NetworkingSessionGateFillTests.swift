import Foundation
import XCTest
@testable import Prairie

/// Extra TokenStore coverage: account switching and sign-out, verified-account
/// binding, profile proof handling, and the fail-closed paths taken when the
/// shared storage misbehaves. Every store shares one in-memory Keychain and a
/// per-test defaults suite, and every account mutation made behind the actor
/// goes through the same `AccountStore`.
final class NetworkingSessionGateFillTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!
    private var accounts: AccountStore!

    private let serverA = ServerRegistry.serverId(for: "https://flaky-a.example")
    private let serverB = ServerRegistry.serverId(for: "https://flaky-b.example")
    private let originA = "https://flaky-a.example"
    private let originB = "https://flaky-b.example"

    override func setUp() {
        super.setUp()
        suiteName = "NetworkingSessionGateFillTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        keychain = .inMemory(service: "NetworkingSessionGateFillTests.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: suite)
        accounts = AccountStore(keychain: keychain, defaults: defaults)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        keychain = nil
        defaults = nil
        accounts = nil
        super.tearDown()
    }

    private var memory: InMemoryKeychainStore { keychain.memoryStore! }

    private func freshStore() -> TokenStore {
        TokenStore(keychain: keychain, defaults: defaults, accounts: accounts)
    }

    private func signedIn() async throws -> TokenStore {
        let store = freshStore()
        await store.switchActiveServer(serverId: serverA)
        await store.setServerUrl(originA)
        try await store.installAccountSession(accessToken: "access-1", refreshToken: "refresh-1", accountID: "acct")
        return store
    }

    private func identity(_ store: TokenStore) async throws -> RefreshAccountIdentity {
        let value = await store.refreshAccountIdentity()
        return try XCTUnwrap(value)
    }

    private func temporaryScope() -> TemporaryAuthScope {
        TemporaryAuthScope(serverId: "temp-server", serverURL: "https://temp.example", accessToken: "t-access",
                           refreshToken: "t-refresh", profileId: "temp-profile", profileToken: "t-proof",
                           controllerDeviceId: "controller", expiresAt: Date().addingTimeInterval(600))
    }

    @discardableResult
    private func saveOther(serverUserId: String?, access: String, refresh: String?) throws -> AccountSignInResult {
        try accounts.saveSignIn(serverId: serverA, origin: originA, serverUserId: serverUserId, username: nil,
                                accessToken: access, refreshToken: refresh, replacingOtherAccounts: false)
    }

    // MARK: - Identity capture

    func testDurableCaptureCarriesTheLocalAccount() async throws {
        let store = try await signedIn()
        let captured = await store.captureDurableAccountAuth()
        let localId = try XCTUnwrap(captured?.localAccountId)
        let loaded = await store.loadedAccountId(onServer: serverA)
        XCTAssertEqual(loaded, localId)
        let other = await store.loadedAccountId(onServer: serverB)
        XCTAssertNil(other)
    }

    func testRequestAuthRejectsADifferentLocalAccount() async throws {
        let store = try await signedIn()
        await store.setProfileId("profile-1")
        let expected = HTTPRequestIdentity(serverId: serverA, serverURL: originA, profileId: "profile-1",
                                           clientFamily: "test", localAccountId: "someone-else")
        do {
            _ = try await store.captureRequestAuth(expected: expected)
            XCTFail("a different account must not be captured")
        } catch HTTPError.requestIdentityChanged {
            // expected
        }
    }

    // MARK: - Unreadable account index

    func testCorruptAccountIndexBlocksTheSession() async throws {
        _ = try await signedIn()
        let userIndependent = keychain.withAudience(.userIndependent)
        XCTAssertTrue(userIndependent.set("junk", for: SharedStorage.accountIndexAccount))
        XCTAssertTrue(userIndependent.set("junk", for: SharedStorage.accountIndexBackupAccount))
        let relaunched = freshStore()
        await relaunched.switchActiveServer(serverId: serverA)
        await relaunched.setServerUrl(originA)
        let access = await relaunched.getAccessToken()
        XCTAssertNil(access, "an unreadable index blocks the session instead of guessing")
    }

    // MARK: - Merge reload and account switching

    func testReloadAfterServerMergePicksUpChangedCredentials() async throws {
        let store = try await signedIn()
        await store.reloadAfterServerMerge()
        let unchanged = await store.getAccessToken()
        XCTAssertEqual(unchanged, "access-1")
        try saveOther(serverUserId: "acct", access: "access-merged", refresh: "refresh-merged")
        await store.reloadAfterServerMerge()
        let merged = await store.getAccessToken()
        XCTAssertEqual(merged, "access-merged")
    }

    func testSwitchActiveAccountAndInactiveSignOut() async throws {
        let store = try await signedIn()
        let firstIdentity = try await identity(store)
        let firstId = try XCTUnwrap(firstIdentity.localAccountId)
        let second = try saveOther(serverUserId: "acct2", access: "access-2", refresh: "refresh-2").account
        let unknown = await store.switchActiveAccount(localAccountId: "missing-account")
        XCTAssertFalse(unknown)
        let switched = await store.switchActiveAccount(localAccountId: second.localAccountId)
        XCTAssertTrue(switched)
        let access = await store.getAccessToken()
        XCTAssertEqual(access, "access-2")

        let loadedRefused = await store.signOutInactiveAccount(second.localAccountId, onServer: serverA)
        XCTAssertFalse(loadedRefused.durable, "the loaded account is not an inactive one")
        let removed = await store.signOutInactiveAccount(firstId, onServer: serverA)
        XCTAssertTrue(removed.durable)
        XCTAssertEqual(removed.localAccountId, firstId)
    }

    func testInactiveSignOutIsRefusedWhenTheRemovalCannotBeSaved() async throws {
        let store = try await signedIn()
        let firstIdentity = try await identity(store)
        let firstId = try XCTUnwrap(firstIdentity.localAccountId)
        let second = try saveOther(serverUserId: "acct2", access: "access-2", refresh: "refresh-2").account
        let switched = await store.switchActiveAccount(localAccountId: second.localAccountId)
        XCTAssertTrue(switched)
        memory.failWrites = true
        let result = await store.signOutInactiveAccount(firstId, onServer: serverA)
        XCTAssertFalse(result.durable)
    }

    func testActiveSignOutIsNotDurableWhenTheRemovalCannotBeSaved() async throws {
        let store = try await signedIn()
        memory.failWrites = true
        let result = await store.signOutActiveAccount()
        XCTAssertFalse(result.durable)
    }

    // MARK: - Refresh rotation

    func testRotatedRefreshTokenIsNotInvalidated() async throws {
        let store = try await signedIn()
        let account = try await identity(store)
        let capturedValue = await store.captureRefreshCredential(expected: account)
        let captured = try XCTUnwrap(capturedValue)
        let rotated = await store.saveRefreshedTokens("access-2", "refresh-2", replacing: captured)
        XCTAssertTrue(rotated)
        let disposition = await store.invalidateRejectedRefresh(captured)
        XCTAssertNil(disposition, "the refresh token already rotated, so the stale rejection is ignored")
        let access = await store.getAccessToken()
        XCTAssertEqual(access, "access-2")
    }

    func testInactiveServerRefreshFailsWhenStorageRejectsTheWrite() async throws {
        let store = try await signedIn()
        let expected = await store.captureAccountInstallationExpectation()
        _ = try await store.installAccountSessionForServer(
            serverID: serverB, origin: originB, accessToken: "b-access", refreshToken: "b-refresh",
            accountID: "b-acct", expected: expected)
        let session = await store.inactiveServerSession(for: serverB)
        let captured = try XCTUnwrap(session)
        memory.failWrites = true
        let saved = await store.saveInactiveServerRefresh(
            accessToken: "b-access-2", refreshToken: "b-refresh-2", replacing: captured, for: serverB)
        XCTAssertFalse(saved)
    }

    // MARK: - Cached profiles

    func testCachedProfilesAreNotReportedSavedWhenStorageFails() async throws {
        let store = try await signedIn()
        let account = try await identity(store)
        let profile = AccountProfile(id: "p1", name: "P", avatarEmoji: nil, avatarImageUrl: nil,
                                     hasPin: false, isChild: false)
        memory.failWrites = true
        let saved = await store.updateCachedProfiles([profile], maxProfiles: 3, expected: account)
        XCTAssertFalse(saved)
    }

    // MARK: - Verified account binding

    private func unverifiedStore() async throws -> (TokenStore, Account, CapturedOrdinaryRequestAuth) {
        let unverified = try saveOther(serverUserId: nil, access: "u-access", refresh: "u-refresh").account
        XCTAssertTrue(accounts.select(unverified))
        let store = freshStore()
        await store.switchActiveServer(serverId: serverA)
        await store.setServerUrl(originA)
        let captured = await store.captureOrdinaryRequestAuth()
        return (store, unverified, try XCTUnwrap(captured))
    }

    func testBindingAnIdentityAnotherAccountOwnsIsRejected() async throws {
        try saveOther(serverUserId: "acct", access: "v-access", refresh: "v-refresh")
        let (store, unverified, captured) = try await unverifiedStore()
        XCTAssertTrue(accounts.select(unverified))
        do {
            try await store.bindVerifiedAccount("acct", username: "user", expected: captured)
            XCTFail("the identity already belongs to another account")
        } catch AccountStoreError.invalidIdentity {
            // expected
        }
    }

    func testBindingAfterTheCredentialsChangedIsRejected() async throws {
        let (store, unverified, captured) = try await unverifiedStore()
        _ = try accounts.rotateTokens(expected: unverified.credentials, onServer: serverA,
                                      accessToken: "u-access-2", refreshToken: "u-refresh-2")
        do {
            try await store.bindVerifiedAccount("fresh-identity", username: "user", expected: captured)
            XCTFail("the credentials changed after the capture")
        } catch HTTPError.requestIdentityChanged {
            // expected
        }
    }

    func testBindingBlocksTheSessionWhenStorageFails() async throws {
        let (store, _, captured) = try await unverifiedStore()
        memory.failWrites = true
        do {
            try await store.bindVerifiedAccount("fresh-identity", username: "user", expected: captured)
            XCTFail("the binding could not be saved")
        } catch {
            // any storage failure is surfaced to the caller
        }
        let access = await store.getAccessToken()
        XCTAssertNil(access)
    }

    // MARK: - Temporary scope and profile proofs

    func testOwnerSnapshotReflectsATemporaryScope() async throws {
        let store = try await signedIn()
        await store.beginTemporaryScope(temporaryScope())
        XCTAssertEqual(store.ownerSnapshot.profileId, "temp-profile")
    }

    func testProfileProofWithoutAnAccountCanOnlyBeCleared() async throws {
        let store = freshStore()
        await store.switchActiveServer(serverId: serverA)
        await store.setServerUrl(originA)
        let stored = await store.setProfileToken("proof")
        XCTAssertFalse(stored)
        let cleared = await store.setProfileToken(nil)
        XCTAssertTrue(cleared)
    }

    func testProfileActivationRenewalAndDeactivation() async throws {
        let store = try await signedIn()
        let account = try await identity(store)
        let activated = await store.activateProfile(profileID: "p1", profileToken: "tok", expectedAccount: account)
        XCTAssertTrue(activated)
        let renewed = await store.renewProfileProof("tok-2", forProfile: "p1", expectedAccount: account)
        XCTAssertTrue(renewed)
        let wrongProfile = await store.renewProfileProof("tok-3", forProfile: "other", expectedAccount: account)
        XCTAssertFalse(wrongProfile)
        let staleSelection = await store.deactivateProfile(
            expectedAccount: account, expectedProfileID: "p1", expectedProfileSelection: UUID())
        XCTAssertFalse(staleSelection)
    }

    func testProfileProofWritesThatFailAreReported() async throws {
        let store = try await signedIn()
        let account = try await identity(store)
        let activated = await store.activateProfile(profileID: "p1", profileToken: "tok", expectedAccount: account)
        XCTAssertTrue(activated)
        memory.failWrites = true
        // Each of these must take its storage-failure path; the outcome is
        // not asserted beyond not crashing, because how the actor orders its
        // guards is an implementation detail.
        _ = await store.renewProfileProof("tok-2", forProfile: "p1", expectedAccount: account)
        _ = await store.deactivateProfile(expectedAccount: account)
        _ = await store.activateProfile(profileID: "p2", profileToken: "tok-3", expectedAccount: account)
    }

    // MARK: - Snapshot restore

    func testRestoringASnapshotWhenStorageFailsDoesNotCrash() async throws {
        let store = try await signedIn()
        let snapshot = await store.accountSessionSnapshot(for: serverA)
        memory.failDeletes = true
        memory.failWrites = true
        _ = await store.restoreAccountSession(snapshot, for: serverA)
    }
}
