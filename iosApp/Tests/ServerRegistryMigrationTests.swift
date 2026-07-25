//
//  ServerRegistryMigrationTests.swift
//  PrairieTests
//
//  Upgrade-persistence: legacy single-server UserDefaults + Keychain must
//  become a multi-server registry entry without dropping login tokens, and
//  re-init ("upgrade relaunch") must keep the session.
//

import XCTest
import Foundation
@testable import Prairie

@MainActor
final class ServerRegistryMigrationTests: XCTestCase {

    private var suiteName: String!
    private var standardName: String!
    private var keychainService: String!
    private var suite: UserDefaults!
    private var standard: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ServerRegistryMigrationTests.suite.\(UUID().uuidString)"
        standardName = "ServerRegistryMigrationTests.standard.\(UUID().uuidString)"
        keychainService = "ServerRegistryMigrationTests.keychain.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        standard = UserDefaults(suiteName: standardName)!
        keychain = SharedKeychain(service: keychainService, accessGroup: nil)
        defaults = SharedDefaults(suite: suite, standard: standard)
    }

    override func tearDown() {
        for account in [
            "com.continuum.app.accessToken",
            "com.continuum.app.refreshToken",
            "com.continuum.app.profileToken",
        ] {
            keychain.delete(account)
        }
        // Best-effort cleanup of any per-server keys we may have written.
        if let url = defaults.string(forKey: "serverUrl"), !url.isEmpty {
            let id = ServerRegistry.serverId(for: url)
            keychain.delete(TokenStore.accessTokenKey(for: id))
            keychain.delete(TokenStore.refreshTokenKey(for: id))
            keychain.delete(TokenStore.profileTokenKey(for: id))
        }
        suite.removePersistentDomain(forName: suiteName)
        standard.removePersistentDomain(forName: standardName)
        suite = nil
        standard = nil
        keychain = nil
        defaults = nil
        super.tearDown()
    }

    private func seedLegacySingleServer(
        url: String = "https://home.example/",
        profileId: String = "profile-1",
        access: String = "ACCESS-LEGACY",
        refresh: String = "REFRESH-LEGACY",
        profileToken: String = "PROFILE-LEGACY"
    ) {
        defaults.set(url, forKey: "serverUrl")
        defaults.set(profileId, forKey: "profileId")
        XCTAssertTrue(keychain.set(access, for: "com.continuum.app.accessToken"))
        XCTAssertTrue(keychain.set(refresh, for: "com.continuum.app.refreshToken"))
        XCTAssertTrue(keychain.set(profileToken, for: "com.continuum.app.profileToken"))
    }

    func testMigrateLegacyIfNeededRekeysTokensAndDeletesLegacyOnlyAfterSet() {
        seedLegacySingleServer()

        let registry = ServerRegistry(defaults: defaults, keychain: keychain)
        let normalized = ServerRegistry.normalize(url: "https://home.example/")
        let id = ServerRegistry.serverId(for: normalized)

        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertEqual(registry.activeServerId, id)
        XCTAssertEqual(registry.activeServer?.url, normalized)
        XCTAssertEqual(registry.activeServer?.profileId, "profile-1")
        XCTAssertTrue(defaults.bool(forKey: "continuumServerRegistry.migrated.v1"))

        // New per-server slots hold the migrated secrets.
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: id)), "ACCESS-LEGACY")
        XCTAssertEqual(keychain.get(TokenStore.refreshTokenKey(for: id)), "REFRESH-LEGACY")
        XCTAssertEqual(keychain.get(TokenStore.profileTokenKey(for: id)), "PROFILE-LEGACY")

        // Legacy fixed-name accounts are gone after successful set.
        XCTAssertNil(keychain.get("com.continuum.app.accessToken"))
        XCTAssertNil(keychain.get("com.continuum.app.refreshToken"))
        XCTAssertNil(keychain.get("com.continuum.app.profileToken"))

        // Active-server mirrors stay so sync callers keep working.
        XCTAssertEqual(defaults.string(forKey: "serverUrl"), normalized)
        XCTAssertEqual(defaults.string(forKey: "profileId"), "profile-1")
    }

    func testMigrateLegacyIsIdempotentAcrossRelaunch() {
        seedLegacySingleServer(url: "https://media.lan")

        _ = ServerRegistry(defaults: defaults, keychain: keychain)
        let id = ServerRegistry.serverId(for: "https://media.lan")

        // Second init simulates an upgrade relaunch — must not wipe login.
        let again = ServerRegistry(defaults: defaults, keychain: keychain)
        XCTAssertEqual(again.entries.count, 1)
        XCTAssertEqual(again.activeServerId, id)
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: id)), "ACCESS-LEGACY")
        XCTAssertEqual(keychain.get(TokenStore.refreshTokenKey(for: id)), "REFRESH-LEGACY")
        XCTAssertEqual(keychain.get(TokenStore.profileTokenKey(for: id)), "PROFILE-LEGACY")
    }

    func testNormalizeAndServerIdAreStable() {
        XCTAssertEqual(ServerRegistry.normalize(url: "  https://a.example///  "), "https://a.example")
        let a = ServerRegistry.serverId(for: "https://a.example/")
        let b = ServerRegistry.serverId(for: "https://a.example")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, ServerRegistry.serverId(for: "https://b.example"))
    }

    func testDisplayNameFallsBackToURL() {
        let bare = ServerEntry(
            id: "x",
            url: "https://x.example",
            fetchedName: nil,
            profileId: nil,
            lastUsedAt: Date()
        )
        XCTAssertEqual(bare.displayName, "https://x.example")
        var named = bare
        named.fetchedName = "Home"
        XCTAssertEqual(named.displayName, "Home")
    }

    func testAddOrUpdatePreservesProfileByDefault() {
        let registry = ServerRegistry(defaults: defaults, keychain: keychain)
        let id = ServerRegistry.serverId(for: "https://home.example")
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://home.example",
            fetchedName: "Home",
            profileId: "P1",
            lastUsedAt: Date()
        ))
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://home.example",
            fetchedName: "Home 2",
            profileId: nil,
            lastUsedAt: Date()
        ))
        XCTAssertEqual(registry.entry(with: id)?.profileId, "P1")
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Home 2")
    }

    func testPersistedRegistrySurvivesReinitWithoutClearingOnVersionBump() {
        let registry = ServerRegistry(defaults: defaults, keychain: keychain)
        let id = ServerRegistry.serverId(for: "https://persist.example")
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://persist.example",
            fetchedName: "Persist",
            profileId: "prof",
            lastUsedAt: Date()
        ))
        XCTAssertTrue(keychain.set("TOK", for: TokenStore.accessTokenKey(for: id)))

        // Re-create with the same stores — no version-bump wipe path exists;
        // registry + token must still be present.
        let reloaded = ServerRegistry(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.entry(with: id)?.fetchedName, "Persist")
        XCTAssertEqual(reloaded.entry(with: id)?.profileId, "prof")
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: id)), "TOK")
    }

    func testEmptyLegacyStateMarksMigratedWithoutEntries() {
        let registry = ServerRegistry(defaults: defaults, keychain: keychain)
        XCTAssertTrue(registry.entries.isEmpty)
        XCTAssertNil(registry.activeServerId)
        XCTAssertTrue(defaults.bool(forKey: "continuumServerRegistry.migrated.v1"))
    }

    func testPartialMigrationRetryPinsLegacyOriginNotMutableServerUrl() {
        // Simulate a failed mid-migration relaunch: legacy tokens remain,
        // migrated flag is unset, but the user changed the active-server
        // mirror to a different host before retry.
        let home = "https://home.example"
        let evil = "https://evil.example"
        let homeId = ServerRegistry.serverId(for: home)
        let evilEntry = ServerEntry(
            id: ServerRegistry.serverId(for: evil),
            url: evil,
            fetchedName: "Evil",
            profileId: nil,
            lastUsedAt: Date()
        )
        struct Wire: Codable {
            var activeServerId: String?
            var entries: [ServerEntry]
        }
        let wireData = try! JSONEncoder().encode(Wire(activeServerId: evilEntry.id, entries: [evilEntry]))
        defaults.set(wireData, forKey: "continuumServerRegistry.v1")
        defaults.set(evil, forKey: "serverUrl")
        defaults.set(home, forKey: "continuumServerRegistry.legacySourceUrl.v1")
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        XCTAssertTrue(keychain.set("ACCESS-HOME", for: "com.continuum.app.accessToken"))
        XCTAssertTrue(keychain.set("REFRESH-HOME", for: "com.continuum.app.refreshToken"))
        XCTAssertTrue(keychain.set("PROFILE-HOME", for: "com.continuum.app.profileToken"))

        let registry = ServerRegistry(defaults: defaults, keychain: keychain)

        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: homeId)), "ACCESS-HOME")
        XCTAssertEqual(keychain.get(TokenStore.refreshTokenKey(for: homeId)), "REFRESH-HOME")
        XCTAssertNil(keychain.get(TokenStore.accessTokenKey(for: evilEntry.id)))
        XCTAssertNil(keychain.get("com.continuum.app.accessToken"))
        XCTAssertTrue(registry.entries.contains(where: { $0.id == homeId }))
        XCTAssertTrue(defaults.bool(forKey: "continuumServerRegistry.migrated.v1"))
        XCTAssertNil(defaults.string(forKey: "continuumServerRegistry.legacySourceUrl.v1"))
    }

    func testSetProfileIdUpdateFetchedNameAndSortedEntries() {
        let registry = ServerRegistry(defaults: defaults, keychain: keychain)
        let older = ServerEntry(
            id: "old",
            url: "https://old.example",
            fetchedName: "Old",
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ServerEntry(
            id: "new",
            url: "https://new.example",
            fetchedName: nil,
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 100)
        )
        registry.addOrUpdate(older)
        registry.addOrUpdate(newer)
        registry.setProfileId("p-new", for: "new")
        registry.updateFetchedName(for: "new", fetchedName: "New Name")

        XCTAssertEqual(registry.entry(with: "new")?.profileId, "p-new")
        XCTAssertEqual(registry.entry(with: "new")?.fetchedName, "New Name")
        XCTAssertEqual(registry.sortedEntries.map(\.id), ["new", "old"])
        XCTAssertFalse(registry.hasActiveServer)
    }
}
