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
            keychain.delete(SharedStorage.accessTokenAccount(for: id))
            keychain.delete(SharedStorage.refreshTokenAccount(for: id))
            keychain.delete(SharedStorage.profileTokenAccount(for: id))
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

    /// A registry entry as builds before the profile split saved it, with
    /// the profile on the server (same shape as ProfileLaunchMigrationTests).
    private struct LegacyRegistryState: Codable {
        let activeServerId: String?
        let entries: [LegacyServerEntry]
    }

    private struct LegacyServerEntry: Codable {
        let id: String
        let url: String
        let fetchedName: String?
        let profileId: String?
        let lastUsedAt: Date
    }

    private func seedLegacyRegistry(_ entries: [LegacyServerEntry]) throws {
        defaults.set(
            try JSONEncoder().encode(LegacyRegistryState(activeServerId: nil, entries: entries)),
            forKey: ServerRegistry.defaultsKey
        )
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

    // tvOS keeps the registry in the shared Keychain, and this suite's
    // fixture only seeds the iOS/macOS defaults-backed store.
    #if !os(tvOS)
    func testMigrateLegacyIsIdempotentAcrossRelaunch() throws {
        seedLegacySingleServer(url: "https://media.lan")

        _ = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://media.lan")

        // Second init simulates an upgrade relaunch — must not wipe login.
        let again = makeRegistry()
        XCTAssertEqual(again.entries.count, 1)
        XCTAssertEqual(again.activeServerId, id)
        // AccountMigration moves the session into one account and deletes
        // the per-server slots; a relaunch must not add a second account.
        let store = AccountStore(keychain: keychain, defaults: defaults)
        let accounts = try store.accounts(onServer: id)
        XCTAssertEqual(accounts.count, 1)
        let account = try XCTUnwrap(accounts.first)
        XCTAssertEqual(account.accessToken, "ACCESS-LEGACY")
        XCTAssertEqual(account.refreshToken, "REFRESH-LEGACY")
        XCTAssertEqual(store.profileToken(for: account.localAccountId, onServer: id), "PROFILE-LEGACY")
    }
    #endif

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
            lastUsedAt: Date()
        )
        XCTAssertEqual(bare.displayName, "https://x.example")
        var named = bare
        named.fetchedName = "Home"
        XCTAssertEqual(named.displayName, "Home")
    }

    func testPersistedRegistrySurvivesReinitWithoutClearingOnVersionBump() throws {
        let id = ServerRegistry.serverId(for: "https://persist.example")
        try seedLegacyRegistry([LegacyServerEntry(
            id: id,
            url: "https://persist.example",
            fetchedName: "Persist",
            profileId: "prof",
            lastUsedAt: Date()
        )])
        XCTAssertTrue(keychain.set("TOK", for: SharedStorage.accessTokenAccount(for: id)))
        _ = makeRegistry()

        // Re-create with the same stores: no version-bump wipe path exists,
        // so the registry and token must still be present.
        let reloaded = makeRegistry()
        XCTAssertEqual(reloaded.entry(with: id)?.fetchedName, "Persist")
        // Access token present: the legacy profileId moves into launch prefs,
        // then onto the account the server's session became.
        XCTAssertNil(reloaded.entry(with: id)?.legacyProfileId)
        let account = try XCTUnwrap(
            AccountStore(keychain: keychain, defaults: defaults).accounts(onServer: id).first
        )
        XCTAssertEqual(
            launchPreferences.rememberedProfile(forAccount: account.localAccountId)?.profileID,
            "prof"
        )
        XCTAssertEqual(account.accessToken, "TOK")
    }

    func testSetProfileIdUpdateFetchedNameAndSortedEntries() {
        let registry = makeRegistry()
        let older = ServerEntry(
            id: "old",
            url: "https://old.example",
            fetchedName: "Old",
            lastUsedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ServerEntry(
            id: "new",
            url: "https://new.example",
            fetchedName: nil,
            lastUsedAt: Date(timeIntervalSince1970: 100)
        )
        registry.addOrUpdate(older)
        registry.addOrUpdate(newer)
        registry.updateFetchedName(for: "new", fetchedName: "New Name")

        XCTAssertEqual(registry.entry(with: "new")?.fetchedName, "New Name")
        XCTAssertEqual(registry.sortedEntries.map(\.id), ["new", "old"])
        XCTAssertFalse(registry.hasActiveServer)
    }

    func testAddOrUpdateWithEmptyFetchedNameKeepsName() {
        let registry = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://home.example")
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://home.example",
            fetchedName: "Home",
            lastUsedAt: Date()
        ))
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://home.example",
            fetchedName: "",
            lastUsedAt: Date()
        ))
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
            lastUsedAt: Date()
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
            lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: drop, url: "https://drop.example", fetchedName: "Drop",
            lastUsedAt: Date(timeIntervalSince1970: 1)
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
            lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        registry.addOrUpdate(ServerEntry(
            id: newer, url: "https://newer.example", fetchedName: "Newer",
            lastUsedAt: Date(timeIntervalSince1970: 100)
        ))
        await registry.switchTo(serverId: older)
        XCTAssertEqual(registry.sortedEntries.map(\.id), [older, newer])
    }

}
