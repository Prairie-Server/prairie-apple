import Foundation
import XCTest
@testable import Prairie

/// TokenStore's canonical account sessions after the API v2 sync: install and
/// verification, durable authority, ownership fences, request capture,
/// session snapshots and restore, sign-out and deletion, profile activation,
/// account epochs and expiry-event routing. Backed by in-memory keychains.
final class TokenStoreSessionTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!

    private let serverA = ServerRegistry.serverId(for: "https://session-a.example")
    private let serverB = ServerRegistry.serverId(for: "https://session-b.example")

    override func setUp() {
        super.setUp()
        suiteName = "TokenStoreSessionTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        keychain = .inMemory(service: "TokenStoreSessionTests.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: suite)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        keychain = nil
        defaults = nil
        super.tearDown()
    }

    private func signedInStore(accountID: String? = "account-1") async throws -> TokenStore {
        let store = TokenStore(keychain: keychain, defaults: defaults)
        await store.switchActiveServer(serverId: serverA)
        await store.setServerUrl("https://session-a.example/")
        try await store.installAccountSession(accessToken: "access-1", refreshToken: "refresh-1", accountID: accountID)
        await store.setProfileId("profile-1")
        return store
    }

    private func temporaryScope(_ suffix: String = "1") -> TemporaryAuthScope {
        TemporaryAuthScope(
            serverId: "temp-server",
            serverURL: "https://temp.example",
            accessToken: "temp-access-\(suffix)",
            refreshToken: "temp-refresh-\(suffix)",
            profileId: "temp-profile",
            profileToken: "temp-proof",
            controllerDeviceId: "controller",
            expiresAt: Date().addingTimeInterval(600)
        )
    }

    // MARK: - Install

    func testInstallRequiresAnActiveServerAndOrigin() async throws {
        let store = TokenStore(keychain: keychain, defaults: defaults)
        await assertThrowsAsync { try await store.installAccountSession(accessToken: "a", refreshToken: "r", accountID: nil) }
        await store.switchActiveServer(serverId: serverA)
        await assertThrowsAsync { try await store.installAccountSession(accessToken: "a", refreshToken: "r", accountID: nil) }
        await store.setServerUrl("https://session-a.example")
        await assertThrowsAsync { try await store.installAccountSession(accessToken: "", refreshToken: "r", accountID: nil) }
        await assertThrowsAsync { try await store.installAccountSession(accessToken: "a", refreshToken: "r", accountID: "") }
        let saved = await store.saveTokens(accessToken: "", refreshToken: "r")
        XCTAssertFalse(saved)

        try await store.installAccountSession(accessToken: "a", refreshToken: "r", accountID: "acct")
        let access = await store.getAccessToken()
        XCTAssertEqual(access, "a")
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: serverA)), "a")
        XCTAssertNotNil(keychain.get(TokenStore.accountEpochKey(for: serverA)))

        let identity = await store.refreshAccountIdentity()
        let otherAccount = RefreshAccountIdentity(serverId: "x", serverURL: "https://x.example",
                                                  credentialGenerationID: UUID())
        await assertThrowsAsync {
            try await store.installAccountSession(accessToken: "b", refreshToken: "r", accountID: nil,
                                                  expectedAccount: otherAccount)
        }
        try await store.installAccountSession(accessToken: "b", refreshToken: "r2", accountID: nil,
                                              clearProfile: false, expectedAccount: identity)
        let rotated = await store.getRefreshToken()
        XCTAssertEqual(rotated, "r2")
    }

    func testInstallForAnotherServerKeepsTheActiveOwner() async throws {
        let store = try await signedInStore()
        let expectation = await store.captureAccountInstallationExpectation()
        try await store.installAccountSessionForServer(serverID: serverB, origin: "https://session-b.example/",
            accessToken: "b-access", refreshToken: "b-refresh", accountID: "account-b", expected: expectation)
        let activeAccess = await store.getAccessToken()
        let otherAccess = await store.getAccessToken(for: serverB)
        XCTAssertEqual(activeAccess, "access-1")
        XCTAssertEqual(otherAccess, "b-access")
        let epoch = await store.getOrCreateAccountEpoch(for: serverB)
        XCTAssertNotNil(epoch)

        await store.setProfileId("profile-2")
        let stale = TokenStore.AccountInstallationExpectation(account: nil, generation: UUID())
        await assertThrowsAsync {
            try await store.installAccountSessionForServer(serverID: serverB, origin: "https://session-b.example",
                accessToken: "x", refreshToken: "y", accountID: "account-b", expected: stale)
        }
    }

    // MARK: - Durable authority and fences

    func testDurableAuthorityNeedsAVerifiedAccount() async throws {
        let unverified = try await signedInStore(accountID: nil)
        let none = await unverified.captureDurableAccountAuth()
        XCTAssertNil(none, "an unverified session cannot own queued work")

        let requestValue = await unverified.captureOrdinaryRequestAuth()
        let request = try XCTUnwrap(requestValue)
        try await unverified.bindVerifiedAccount("account-9", expected: request)
        let boundValue = await unverified.captureDurableAccountAuth()
        let bound = try XCTUnwrap(boundValue)
        XCTAssertEqual(bound.accountID, "account-9")
        // Binding the same account again is a no-op; a different one is refused.
        try await unverified.bindVerifiedAccount("account-9", expected: request)
        await assertThrowsAsync { try await unverified.bindVerifiedAccount("account-other", expected: request) }
        await assertThrowsAsync { try await unverified.bindVerifiedAccount("", expected: request) }

        try await unverified.withCurrentDurableAuthority(bound) {}
        await unverified.setProfileId("profile-2")
        await assertThrowsAsync { try await unverified.withCurrentDurableAuthority(bound) {} }

        await unverified.beginTemporaryScope(temporaryScope())
        let temporary = await unverified.captureDurableAccountAuth()
        XCTAssertNil(temporary, "temporary playback credentials cannot own queued work")
        try await unverified.bindVerifiedAccount("ignored", expected: request)
    }

    func testOwnerFenceRejectsAnOwnerChangeOnEitherSide() async throws {
        let store = try await signedInStore()
        let authValue = await store.captureOrdinaryRequestAuth()
        let auth = try XCTUnwrap(authValue)
        let value = try await store.withOwnerFence(auth) { 7 }
        XCTAssertEqual(value, 7)

        await assertThrowsAsync {
            _ = try await store.withOwnerFence(auth) {
                await store.setProfileId("profile-2")
                return 1
            }
        }
        await assertThrowsAsync { _ = try await store.withOwnerFence(auth) { 1 } }
        let rematched = await store.currentOrdinaryRequestAuth(matchingIdentityOf: auth)
        XCTAssertNil(rematched)
    }

    func testRequestCaptureMatchesTheExpectedIdentity() async throws {
        let store = try await signedInStore()
        let expected = HTTPRequestIdentity(serverId: serverA, serverURL: "https://session-a.example",
                                           profileId: "profile-1", clientFamily: "ios")
        let captured = try await store.captureRequestAuth(expected: expected)
        XCTAssertEqual(captured.accessToken, "access-1")
        XCTAssertEqual(captured.profileId, "profile-1")
        XCTAssertEqual(captured.credentialOwner, .persistentServer(serverId: serverA))

        for wrong in [
            HTTPRequestIdentity(serverId: "", serverURL: "https://session-a.example", profileId: "profile-1", clientFamily: "ios"),
            HTTPRequestIdentity(serverId: serverA, serverURL: "", profileId: "profile-1", clientFamily: "ios"),
            HTTPRequestIdentity(serverId: serverA, serverURL: "https://session-a.example", profileId: "", clientFamily: "ios"),
            HTTPRequestIdentity(serverId: serverB, serverURL: "https://session-a.example", profileId: "profile-1", clientFamily: "ios"),
            HTTPRequestIdentity(serverId: serverA, serverURL: "https://elsewhere.example", profileId: "profile-1", clientFamily: "ios"),
            HTTPRequestIdentity(serverId: serverA, serverURL: "https://session-a.example", profileId: "profile-2", clientFamily: "ios"),
        ] {
            await assertThrowsAsync { _ = try await store.captureRequestAuth(expected: wrong) }
        }

        await store.beginTemporaryScope(temporaryScope())
        let temporary = try await store.captureRequestAuth(expected: HTTPRequestIdentity(
            serverId: "temp-server", serverURL: "https://temp.example", profileId: "temp-profile", clientFamily: "tvos"))
        XCTAssertEqual(temporary.credentialOwner, .temporary)
        XCTAssertEqual(temporary.accessToken, "temp-access-1")

        let empty = TokenStore(keychain: .inMemory(service: "empty.\(UUID().uuidString)"), defaults: defaults)
        await assertThrowsAsync { _ = try await empty.captureRequestAuth(expected: expected) }
    }

    func testMismatchReasonsNameTheFieldThatMoved() {
        func reason(_ flags: [Bool]) -> String {
            TokenStore.requestIdentityMismatchReason(
                hasExpectedServerId: flags[0], hasExpectedServerURL: flags[1], hasExpectedProfileId: flags[2],
                serverIdMatches: flags[3], serverURLMatches: flags[4], accountServerIdMatches: flags[5],
                accountServerURLMatches: flags[6], profileMatches: flags[7])
        }
        var seen = Set<String>()
        for index in 0..<8 {
            var flags = Array(repeating: true, count: 8)
            flags[index] = false
            seen.insert(reason(flags))
        }
        XCTAssertEqual(seen.count, 8, "\(seen)")
        XCTAssertEqual(reason(Array(repeating: false, count: 8)), "missingServerId")
    }

    // MARK: - Temporary scopes

    func testTemporaryScopeLifecycle() async throws {
        let store = try await signedInStore()
        let absent = await store.endTemporaryScope()
        XCTAssertEqual(absent, .alreadyAbsent)

        let first = temporaryScope("1")
        let snapshot = await store.beginTemporaryScope(first)
        XCTAssertNil(snapshot.scope)
        let id = await store.getActiveServerId()
        XCTAssertEqual(id, "temp-server")
        let url = await store.getServerUrl()
        XCTAssertEqual(url, "https://temp.example")
        await store.setProfileId("temp-profile-2")
        let profile = await store.getProfileId()
        XCTAssertEqual(profile, "temp-profile-2")
        let proofSet = await store.setProfileToken(nil)
        XCTAssertFalse(proofSet)
        let epoch = await store.getOrCreateAccountEpoch()
        XCTAssertNil(epoch)
        let activated = await store.activateProfile(profileID: "x", profileToken: nil,
            expectedAccount: RefreshAccountIdentity(serverId: "temp-server", serverURL: "https://temp.example",
                                                    credentialGenerationID: first.credentialGenerationID))
        XCTAssertFalse(activated)
        let deactivated = await store.deactivateProfile(expectedAccount: nil)
        XCTAssertFalse(deactivated)

        let mismatch = await store.endTemporaryScope(expectedGenerationID: UUID())
        XCTAssertEqual(mismatch, .differentGeneration(activeGenerationID: first.credentialGenerationID))

        let expectation = await store.captureAccountInstallationExpectation()
        let second = temporaryScope("2")
        let replaced = await store.beginTemporaryScope(second, expected: expectation)
        XCTAssertEqual(replaced?.scope?.credentialGenerationID, first.credentialGenerationID)
        let refused = await store.beginTemporaryScope(temporaryScope("3"),
            expected: TokenStore.AccountInstallationExpectation(account: nil, generation: UUID()))
        XCTAssertNil(refused)

        let ended = await store.endTemporaryScope(expectedGenerationID: second.credentialGenerationID)
        XCTAssertEqual(ended, .ended(second))
        let restoredAccess = await store.getAccessToken()
        XCTAssertEqual(restoredAccess, "access-1")
    }

    // MARK: - Snapshots, sign-out and deletion

    func testSnapshotsRestoreEachSessionState() async throws {
        let store = try await signedInStore()
        await store.setProfileToken("proof-1")
        let session = await store.accountSessionSnapshot(for: serverA)
        guard case .session(let value, let proof) = session else { return XCTFail("\(session)") }
        XCTAssertEqual(value.accessToken, "access-1")
        XCTAssertEqual(proof, "proof-1")
        let unreadable = await store.accountSessionSnapshot(for: "")
        XCTAssertEqual(unreadable, .unreadable)

        let cleared = await store.clearTokens()
        XCTAssertTrue(cleared)
        let afterClear = await store.getAccessToken()
        XCTAssertNil(afterClear)
        let signedOut = await store.accountSessionSnapshot(for: serverA)
        guard case .signedOut = signedOut else { return XCTFail("\(signedOut)") }

        let restored = await store.restoreAccountSession(session, for: serverA)
        XCTAssertTrue(restored)
        let restoredAccess = await store.getAccessToken()
        let restoredProof = await store.getProfileToken()
        XCTAssertEqual(restoredAccess, "access-1")
        XCTAssertEqual(restoredProof, "proof-1")

        let backToSignedOut = await store.restoreAccountSession(signedOut, for: serverA)
        XCTAssertTrue(backToSignedOut)
        let signedOutAccess = await store.getAccessToken()
        XCTAssertNil(signedOutAccess)

        let legacy = TokenStore.AccountSessionSnapshot.legacy(accessToken: "legacy-a", refreshToken: "legacy-r",
                                                              epoch: nil, profileToken: nil)
        let legacyRestored = await store.restoreAccountSession(legacy, for: serverA)
        XCTAssertTrue(legacyRestored)
        let legacyAccess = await store.getAccessToken()
        XCTAssertEqual(legacyAccess, "legacy-a")
        let legacyEpoch = await store.getOrCreateAccountEpoch()
        XCTAssertNotNil(legacyEpoch, "a legacy session gets an epoch on first use")
        let legacyEpochAgain = await store.getOrCreateAccountEpoch(for: serverA)
        XCTAssertEqual(legacyEpochAgain, legacyEpoch)

        let failed = await store.restoreAccountSession(.unreadable, for: serverA)
        XCTAssertFalse(failed)
        let neverInstalled = await store.getAccessToken(for: serverB)
        XCTAssertNil(neverInstalled)
        let emptyServer = await store.restoreAccountSession(session, for: "")
        XCTAssertFalse(emptyServer)
    }

    func testDeleteTokensAndStoredProofs() async throws {
        let store = try await signedInStore()
        let expectation = await store.captureAccountInstallationExpectation()
        try await store.installAccountSessionForServer(serverID: serverB, origin: "https://session-b.example",
            accessToken: "b-access", refreshToken: "b-refresh", accountID: "account-b", expected: expectation)
        let hasOther = await store.hasStoredProfileToken(for: serverB)
        XCTAssertFalse(hasOther)
        let hasNone = await store.hasStoredProfileToken(for: "")
        XCTAssertFalse(hasNone)

        let deletedOther = await store.deleteTokens(for: serverB)
        XCTAssertTrue(deletedOther)
        let otherAfter = await store.getAccessToken(for: serverB)
        XCTAssertNil(otherAfter)
        let otherEpoch = await store.getOrCreateAccountEpoch(for: serverB)
        XCTAssertNil(otherEpoch, "a deleted server stays blocked for the process")
        let noop = await store.deleteTokens(for: "")
        XCTAssertTrue(noop)

        let deletedActive = await store.deleteTokens(for: serverA)
        XCTAssertTrue(deletedActive)
        let activeAfter = await store.getAccessToken()
        XCTAssertNil(activeAfter)
        let noAccess = await store.getAccessToken(for: "")
        XCTAssertNil(noAccess)
    }

    func testProfileActivationFollowsTheExpectedAccount() async throws {
        let store = try await signedInStore()
        let accountValue = await store.refreshAccountIdentity()
        let account = try XCTUnwrap(accountValue)
        let wrong = RefreshAccountIdentity(serverId: serverB, serverURL: "https://session-b.example",
                                           credentialGenerationID: UUID())

        let refused = await store.activateProfile(profileID: "profile-3", profileToken: "p3", expectedAccount: wrong)
        XCTAssertFalse(refused)
        let empty = await store.activateProfile(profileID: "", profileToken: "p3", expectedAccount: account)
        XCTAssertFalse(empty)
        let activated = await store.activateProfile(profileID: "profile-3", profileToken: "p3", expectedAccount: account)
        XCTAssertTrue(activated)
        let proof = await store.getProfileToken()
        XCTAssertEqual(proof, "p3")
        let withoutProof = await store.activateProfile(profileID: "profile-4", profileToken: nil, expectedAccount: account)
        XCTAssertTrue(withoutProof)
        let hasProof = await store.hasStoredProfileToken(for: serverA)
        XCTAssertFalse(hasProof)

        let wrongAccount = await store.deactivateProfile(expectedAccount: wrong)
        XCTAssertFalse(wrongAccount)
        let wrongProfile = await store.deactivateProfile(expectedAccount: account, expectedProfileID: "profile-9")
        XCTAssertFalse(wrongProfile)
        let deactivated = await store.deactivateProfile(expectedAccount: account, expectedProfileID: "profile-4")
        XCTAssertTrue(deactivated)
        let profile = await store.getProfileId()
        XCTAssertNil(profile)
    }

    // MARK: - Expiry events

    func testExpiryEventsOnlyRouteForTheirOwnCredentialState() async throws {
        let store = try await signedInStore()
        let accountValue = await store.refreshAccountIdentity()
        let account = try XCTUnwrap(accountValue)
        let persistent = SessionExpiryEvent(account: account, disposition: .persistentSessionCleared)
        let whileSignedIn = await store.shouldConsumeSessionExpiryEvent(persistent)
        XCTAssertFalse(whileSignedIn, "credentials are still installed")

        let other = SessionExpiryEvent(account: RefreshAccountIdentity(serverId: serverB,
            serverURL: "https://session-b.example", credentialGenerationID: UUID()), disposition: .persistentSessionCleared)
        let foreign = await store.shouldConsumeSessionExpiryEvent(other)
        XCTAssertFalse(foreign)

        let captureValue = await store.captureRefreshCredential(expected: account)
        let capture = try XCTUnwrap(captureValue)
        let disposition = await store.invalidateRejectedRefresh(capture)
        XCTAssertEqual(disposition, .persistentSessionCleared)
        let clearedAccountValue = await store.refreshAccountIdentity()
        let clearedAccount = try XCTUnwrap(clearedAccountValue)
        await store.setProfileId(nil)
        let afterClear = await store.shouldConsumeSessionExpiryEvent(
            SessionExpiryEvent(account: clearedAccount, disposition: .persistentSessionCleared))
        XCTAssertTrue(afterClear)

        let scope = temporaryScope()
        await store.beginTemporaryScope(scope)
        let temporaryAccountValue = await store.refreshAccountIdentity()
        let temporaryAccount = try XCTUnwrap(temporaryAccountValue)
        let temporaryEvent = SessionExpiryEvent(account: temporaryAccount, disposition: .temporarySessionExpired)
        let beforeRejection = await store.shouldConsumeSessionExpiryEvent(temporaryEvent)
        XCTAssertFalse(beforeRejection)
        let temporaryCaptureValue = await store.captureRefreshCredential(expected: temporaryAccount)
        let temporaryCapture = try XCTUnwrap(temporaryCaptureValue)
        let temporaryDisposition = await store.invalidateRejectedRefresh(temporaryCapture)
        XCTAssertEqual(temporaryDisposition, .temporarySessionExpired)
        let afterRejection = await store.shouldConsumeSessionExpiryEvent(temporaryEvent)
        XCTAssertTrue(afterRejection)
        let rejectedCapture = await store.captureRefreshCredential(expected: temporaryAccount)
        XCTAssertNil(rejectedCapture, "a rejected temporary credential is not offered again")
    }
}

private func assertThrowsAsync(
    _ body: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await body()
        XCTFail("expected an error", file: file, line: line)
    } catch {}
}
