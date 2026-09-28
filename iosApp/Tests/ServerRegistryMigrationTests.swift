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
    private var suite: UserDefaults!
    private var standard: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!
    private var launchPreferences: ProfileLaunchPreferences!

    override func setUp() {
        super.setUp()
        suiteName = "ServerRegistryMigrationTests.suite.\(UUID().uuidString)"
        standardName = "ServerRegistryMigrationTests.standard.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        standard = UserDefaults(suiteName: standardName)!
        // In-memory: CI unit tests disable code signing, so SecItem returns -34018.
        keychain = .inMemory(service: "ServerRegistryMigrationTests.keychain.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: standard)
        launchPreferences = ProfileLaunchPreferences(defaults: defaults)
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
        launchPreferences = nil
        super.tearDown()
    }

    private func makeRegistry() -> ServerRegistry {
        ServerRegistry(
            defaults: defaults,
            keychain: keychain,
            launchPreferences: launchPreferences
        )
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

    func testMigrateLegacyIsIdempotentAcrossRelaunch() {
        seedLegacySingleServer(url: "https://media.lan")

        _ = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://media.lan")

        // Second init simulates an upgrade relaunch — must not wipe login.
        let again = makeRegistry()
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

    func testPersistedRegistrySurvivesReinitWithoutClearingOnVersionBump() {
        let registry = makeRegistry()
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
        let reloaded = makeRegistry()
        XCTAssertEqual(reloaded.entry(with: id)?.fetchedName, "Persist")
        // Access token present → legacy profileId migrates into launch prefs.
        XCTAssertNil(reloaded.entry(with: id)?.legacyProfileId)
        XCTAssertEqual(
            launchPreferences.rememberedProfile(for: id)?.profileID,
            "prof"
        )
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: id)), "TOK")
    }

    func testSetProfileIdUpdateFetchedNameAndSortedEntries() {
        let registry = makeRegistry()
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
        registry.updateFetchedName(for: "new", fetchedName: "New Name")

        XCTAssertEqual(registry.entry(with: "new")?.fetchedName, "New Name")
        XCTAssertEqual(registry.sortedEntries.map(\.id), ["new", "old"])
        XCTAssertFalse(registry.hasActiveServer)
    }

    func testAddOrUpdateWithoutPreservingProfileAndEmptyFetchedName() {
        let registry = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://home.example")
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://home.example",
            fetchedName: "Home",
            profileId: "keep-me",
            lastUsedAt: Date()
        ))
        registry.addOrUpdate(
            ServerEntry(
                id: id,
                url: "https://home.example",
                fetchedName: "",
                profileId: nil,
                lastUsedAt: Date()
            ),
            preservingProfile: false
        )
        XCTAssertNil(registry.entry(with: id)?.legacyProfileId)
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Home")

        registry.updateFetchedName(for: id, fetchedName: "")
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Home")
        registry.updateFetchedName(for: "missing", fetchedName: "Nope")
    }

    func testRemoveActiveWithNoFallbackClearsMirrors() async {
        let registry = makeRegistry()
        let only = ServerRegistry.serverId(for: "https://solo.example")
        registry.addOrUpdate(ServerEntry(
            id: only, url: "https://solo.example", fetchedName: "Solo",
            profileId: "solo", lastUsedAt: Date()
        ))
        await registry.switchTo(serverId: only)

        await registry.remove(serverId: only)

        XCTAssertTrue(registry.entries.isEmpty)
        XCTAssertNil(registry.activeServerId)
        XCTAssertNil(defaults.string(forKey: "serverUrl"))
        XCTAssertNil(defaults.string(forKey: "profileId"))
    }

    func testRemoveNonActiveLeavesActiveUntouched() async {
        let registry = makeRegistry()
        let keep = ServerRegistry.serverId(for: "https://keep.example")
        let drop = ServerRegistry.serverId(for: "https://drop.example")
        registry.addOrUpdate(ServerEntry(
            id: keep, url: "https://keep.example", fetchedName: "Keep",
            profileId: "pk", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: drop, url: "https://drop.example", fetchedName: "Drop",
            profileId: "pd", lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        await registry.switchTo(serverId: keep)

        await registry.remove(serverId: drop)

        XCTAssertEqual(registry.activeServerId, keep)
        XCTAssertEqual(defaults.string(forKey: "serverUrl"), "https://keep.example")
        XCTAssertNil(registry.entry(with: drop))
    }

    func testLoadCorruptRegistryStartsEmpty() {
        standard.set(Data("not-json".utf8), forKey: "continuumServerRegistry.v1")
        standard.set(true, forKey: "continuumServerRegistry.migrated.v1")
        let registry = makeRegistry()
        XCTAssertTrue(registry.entries.isEmpty)
        XCTAssertNil(registry.activeServerId)
    }

    func testDisplayNameEmptyFetchedNameFallsBackToURL() {
        var entry = ServerEntry(
            id: "x",
            url: "https://x.example",
            fetchedName: "",
            profileId: nil,
            lastUsedAt: Date()
        )
        XCTAssertEqual(entry.displayName, "https://x.example")
        entry.fetchedName = "Named"
        XCTAssertEqual(entry.displayName, "Named")
    }

    func testSortedEntriesPutsActiveFirst() async {
        let registry = makeRegistry()
        let older = ServerRegistry.serverId(for: "https://older.example")
        let newer = ServerRegistry.serverId(for: "https://newer.example")
        registry.addOrUpdate(ServerEntry(
            id: older, url: "https://older.example", fetchedName: "Older",
            profileId: nil, lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        registry.addOrUpdate(ServerEntry(
            id: newer, url: "https://newer.example", fetchedName: "Newer",
            profileId: nil, lastUsedAt: Date(timeIntervalSince1970: 100)
        ))
        await registry.switchTo(serverId: older)
        XCTAssertEqual(registry.sortedEntries.map(\.id), [older, newer])
    }

}
