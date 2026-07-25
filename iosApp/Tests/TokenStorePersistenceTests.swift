//
//  TokenStorePersistenceTests.swift
//  PrairieTests
//
//  TokenStore must keep per-server Keychain slots and SharedDefaults mirrors
//  across actor re-creation (simulating process death / upgrade relaunch).
//

import XCTest
import Foundation
@testable import Prairie

final class TokenStorePersistenceTests: XCTestCase {

    private var suiteName: String!
    private var standardName: String!
    private var keychainService: String!
    private var suite: UserDefaults!
    private var standard: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TokenStorePersistenceTests.suite.\(UUID().uuidString)"
        standardName = "TokenStorePersistenceTests.standard.\(UUID().uuidString)"
        keychainService = "TokenStorePersistenceTests.keychain.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        standard = UserDefaults(suiteName: standardName)!
        keychain = SharedKeychain(service: keychainService, accessGroup: nil)
        defaults = SharedDefaults(suite: suite, standard: standard)
    }

    override func tearDown() {
        for account in [
            SharedStorage.mirroredAccessTokenAccount,
            SharedStorage.mirroredProfileTokenAccount,
        ] {
            keychain.delete(account)
        }
        suite.removePersistentDomain(forName: suiteName)
        standard.removePersistentDomain(forName: standardName)
        suite = nil
        standard = nil
        keychain = nil
        defaults = nil
        super.tearDown()
    }

    private func makeStore() -> TokenStore {
        TokenStore(keychain: keychain, defaults: defaults)
    }

    func testSaveAndReloadTokensForActiveServer() async {
        let serverId = ServerRegistry.serverId(for: "https://tv.example")
        let store = makeStore()
        await store.setServerUrl("https://tv.example/")
        await store.switchActiveServer(serverId: serverId)
        await store.saveTokens(accessToken: "A1", refreshToken: "R1")
        await store.setProfileToken("P1")
        await store.setProfileId("profile-9")

        XCTAssertEqual(await store.getAccessToken(), "A1")
        XCTAssertEqual(await store.getRefreshToken(), "R1")
        XCTAssertEqual(await store.getProfileToken(), "P1")
        XCTAssertEqual(await store.getProfileId(), "profile-9")
        XCTAssertEqual(await store.getServerUrl(), "https://tv.example")

        // Fresh actor + same Keychain/defaults = upgrade relaunch.
        let again = makeStore()
        await again.switchActiveServer(serverId: serverId)
        XCTAssertEqual(await again.getAccessToken(), "A1")
        XCTAssertEqual(await again.getRefreshToken(), "R1")
        XCTAssertEqual(await again.getProfileToken(), "P1")
        XCTAssertEqual(await again.getProfileId(), "profile-9")
        XCTAssertEqual(await again.getServerUrl(), "https://tv.example")

        // Top Shelf mirrors use stable account names.
        XCTAssertEqual(keychain.get(SharedStorage.mirroredAccessTokenAccount), "A1")
        XCTAssertEqual(keychain.get(SharedStorage.mirroredProfileTokenAccount), "P1")
    }

    func testPerServerSlotsDoNotLeakAcrossServers() async {
        let a = ServerRegistry.serverId(for: "https://a.example")
        let b = ServerRegistry.serverId(for: "https://b.example")
        let store = makeStore()

        await store.switchActiveServer(serverId: a)
        await store.saveTokens(accessToken: "A-A", refreshToken: "R-A")

        await store.switchActiveServer(serverId: b)
        await store.saveTokens(accessToken: "A-B", refreshToken: "R-B")

        XCTAssertEqual(await store.getAccessToken(for: a), "A-A")
        XCTAssertEqual(await store.getAccessToken(for: b), "A-B")
        XCTAssertEqual(await store.getAccessToken(), "A-B")

        await store.deleteTokens(for: b)
        XCTAssertNil(await store.getAccessToken())
        XCTAssertEqual(await store.getAccessToken(for: a), "A-A")
    }

    func testClearTokensLeavesOtherServersIntact() async {
        let a = ServerRegistry.serverId(for: "https://a.example")
        let b = ServerRegistry.serverId(for: "https://b.example")
        let store = makeStore()

        await store.switchActiveServer(serverId: a)
        await store.saveTokens(accessToken: "A-A", refreshToken: "R-A")
        await store.switchActiveServer(serverId: b)
        await store.saveTokens(accessToken: "A-B", refreshToken: "R-B")
        await store.clearTokens()

        XCTAssertNil(await store.getAccessToken())
        XCTAssertEqual(await store.getAccessToken(for: a), "A-A")
        XCTAssertNil(keychain.get(SharedStorage.mirroredAccessTokenAccount))
    }

    func testTemporaryScopeOverridesWithoutTouchingKeychain() async {
        let serverId = ServerRegistry.serverId(for: "https://home.example")
        let store = makeStore()
        await store.switchActiveServer(serverId: serverId)
        await store.saveTokens(accessToken: "PERM", refreshToken: "PERM-R")

        await store.beginTemporaryScope(TemporaryAuthScope(
            serverId: "temp-server",
            serverURL: "https://temp.example",
            accessToken: "TEMP",
            refreshToken: "TEMP-R",
            profileId: "temp-profile",
            profileToken: "TEMP-P",
            controllerDeviceId: "ctrl-1",
            expiresAt: Date().addingTimeInterval(600)
        ))

        XCTAssertTrue(await store.hasTemporaryScope())
        XCTAssertEqual(await store.getAccessToken(), "TEMP")
        XCTAssertEqual(await store.getServerUrl(), "https://temp.example")
        XCTAssertEqual(await store.getProfileId(), "temp-profile")

        let ended = await store.endTemporaryScope()
        XCTAssertEqual(ended?.accessToken, "TEMP")
        XCTAssertEqual(await store.getAccessToken(), "PERM")
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: serverId)), "PERM")
    }

    func testHasAccessTokenForActiveServer() async {
        let serverId = ServerRegistry.serverId(for: "https://home.example")
        let store = makeStore()
        XCTAssertFalse(await store.hasAccessTokenForActiveServer(serverId: serverId))

        await store.switchActiveServer(serverId: serverId)
        await store.saveTokens(accessToken: "YES", refreshToken: "R")
        XCTAssertTrue(await store.hasAccessTokenForActiveServer(serverId: serverId))
    }

    func testKeyDerivationHelpers() {
        XCTAssertEqual(TokenStore.accessTokenKey(for: "abc"), "com.continuum.abc.accessToken")
        XCTAssertEqual(TokenStore.refreshTokenKey(for: "abc"), "com.continuum.abc.refreshToken")
        XCTAssertEqual(TokenStore.profileTokenKey(for: "abc"), "com.continuum.abc.profileToken")
    }

    func testSharedStorageIdentitiesAreStable() {
        // Documented upgrade contract — renaming these orphans installs.
        XCTAssertEqual(SharedStorage.appGroup, "group.org.prairieserver.prairie")
        XCTAssertEqual(SharedStorage.keychainService, "com.continuum.app")
    }
}
