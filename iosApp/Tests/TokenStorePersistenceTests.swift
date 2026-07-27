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
    private var suite: UserDefaults!
    private var standard: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TokenStorePersistenceTests.suite.\(UUID().uuidString)"
        standardName = "TokenStorePersistenceTests.standard.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        standard = UserDefaults(suiteName: standardName)!
        // In-memory: CI unit tests disable code signing, so SecItem returns -34018.
        keychain = .inMemory(service: "TokenStorePersistenceTests.keychain.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: standard)
    }

    override func tearDown() {
        for account in [
            SharedStorage.mirroredAccessTokenAccount,
            SharedStorage.mirroredProfileTokenAccount,
        ] {
            keychain.delete(account)
        }
        for url in [
            "https://tv.example",
            "https://a.example",
            "https://b.example",
            "https://home.example",
        ] {
            let serverId = ServerRegistry.serverId(for: url)
            keychain.delete(TokenStore.accessTokenKey(for: serverId))
            keychain.delete(TokenStore.refreshTokenKey(for: serverId))
            keychain.delete(TokenStore.profileTokenKey(for: serverId))
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

        let value1 = await store.getAccessToken()
        XCTAssertEqual(value1, "A1")
        let value2 = await store.getRefreshToken()
        XCTAssertEqual(value2, "R1")
        let value3 = await store.getProfileToken()
        XCTAssertEqual(value3, "P1")
        let value4 = await store.getProfileId()
        XCTAssertEqual(value4, "profile-9")
        let value5 = await store.getServerUrl()
        XCTAssertEqual(value5, "https://tv.example")

        // Fresh actor + same Keychain/defaults = upgrade relaunch.
        let again = makeStore()
        await again.switchActiveServer(serverId: serverId)
        let value6 = await again.getAccessToken()
        XCTAssertEqual(value6, "A1")
        let value7 = await again.getRefreshToken()
        XCTAssertEqual(value7, "R1")
        let value8 = await again.getProfileToken()
        XCTAssertEqual(value8, "P1")
        let value9 = await again.getProfileId()
        XCTAssertEqual(value9, "profile-9")
        let value10 = await again.getServerUrl()
        XCTAssertEqual(value10, "https://tv.example")

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

        let value11 = await store.getAccessToken(for: a)
        XCTAssertEqual(value11, "A-A")
        let value12 = await store.getAccessToken(for: b)
        XCTAssertEqual(value12, "A-B")
        let value13 = await store.getAccessToken()
        XCTAssertEqual(value13, "A-B")

        await store.deleteTokens(for: b)
        let value14 = await store.getAccessToken()
        XCTAssertNil(value14)
        let value15 = await store.getAccessToken(for: a)
        XCTAssertEqual(value15, "A-A")
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

        let value16 = await store.getAccessToken()
        XCTAssertNil(value16)
        let value17 = await store.getAccessToken(for: a)
        XCTAssertEqual(value17, "A-A")
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

        let value18 = await store.hasTemporaryScope()
        XCTAssertTrue(value18)
        let value19 = await store.getAccessToken()
        XCTAssertEqual(value19, "TEMP")
        let value20 = await store.getServerUrl()
        XCTAssertEqual(value20, "https://temp.example")
        let value21 = await store.getProfileId()
        XCTAssertEqual(value21, "temp-profile")
        // Cover temp-scope accessors / mutators the CI gate otherwise misses.
        let tempScope = await store.getTemporaryScope()
        XCTAssertEqual(tempScope?.serverId, "temp-server")
        let activeId = await store.getActiveServerId()
        XCTAssertEqual(activeId, "temp-server")
        await store.saveTokens(accessToken: "TEMP2", refreshToken: "TEMP2-R")
        await store.setProfileToken("TEMP-P2")
        XCTAssertEqual(await store.getAccessToken(), "TEMP2")
        XCTAssertEqual(await store.getRefreshToken(), "TEMP2-R")
        XCTAssertEqual(await store.getProfileToken(), "TEMP-P2")

        let ended = await store.endTemporaryScope()
        XCTAssertEqual(ended?.accessToken, "TEMP2")
        let value22 = await store.getAccessToken()
        XCTAssertEqual(value22, "PERM")
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: serverId)), "PERM")
    }

    func testTemporaryScopeClearDropsOverrideWithoutTouchingKeychain() async {
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
        await store.clearTokens()
        XCTAssertFalse(await store.hasTemporaryScope())
        XCTAssertEqual(await store.getAccessToken(), "PERM")
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: serverId)), "PERM")
    }

    func testHasAccessTokenForActiveServer() async {
        let serverId = ServerRegistry.serverId(for: "https://home.example")
        let store = makeStore()
        let value23 = await store.hasAccessTokenForActiveServer(serverId: serverId)
        XCTAssertFalse(value23)

        await store.switchActiveServer(serverId: serverId)
        await store.saveTokens(accessToken: "YES", refreshToken: "R")
        let value24 = await store.hasAccessTokenForActiveServer(serverId: serverId)
        XCTAssertTrue(value24)
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
