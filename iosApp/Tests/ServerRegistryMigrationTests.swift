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

    func testMigrateLegacyIfNeededRekeysTokensAndDeletesLegacyOnlyAfterSet() {
        seedLegacySingleServer()

        let registry = makeRegistry()
        let normalized = ServerRegistry.normalize(url: "https://home.example/")
        let id = ServerRegistry.serverId(for: normalized)

        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertEqual(registry.activeServerId, id)
        XCTAssertEqual(registry.activeServer?.url, normalized)
        // Profile identity now lives in ProfileLaunchPreferences; the registry
        // row only keeps a transient legacy field until that migration lands.
        XCTAssertNil(registry.activeServer?.profileId)
        XCTAssertEqual(
            launchPreferences.rememberedProfile(for: id)?.profileID,
            "profile-1"
        )
        XCTAssertTrue(defaults.bool(forKey: "continuumServerRegistry.migrated.v1"))

        // New per-server slots hold the migrated secrets.
        XCTAssertEqual(
            keychain.withAudience(.userIndependent)
                .get(TokenStore.accessTokenKey(for: id)),
            "ACCESS-LEGACY"
        )
        XCTAssertEqual(
            keychain.withAudience(.userIndependent)
                .get(TokenStore.refreshTokenKey(for: id)),
            "REFRESH-LEGACY"
        )
        XCTAssertEqual(
            keychain.withAudience(.currentUser)
                .get(TokenStore.profileTokenKey(for: id)),
            "PROFILE-LEGACY"
        )

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

    func testAddOrUpdatePreservesProfileByDefault() {
        let registry = makeRegistry()
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
        XCTAssertNil(reloaded.entry(with: id)?.profileId)
        XCTAssertEqual(
            launchPreferences.rememberedProfile(for: id)?.profileID,
            "prof"
        )
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: id)), "TOK")
    }

    func testEmptyLegacyStateMarksMigratedWithoutEntries() {
        let registry = makeRegistry()
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

        let registry = makeRegistry()

        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: homeId)), "ACCESS-HOME")
        XCTAssertEqual(keychain.get(TokenStore.refreshTokenKey(for: homeId)), "REFRESH-HOME")
        XCTAssertNil(keychain.get(TokenStore.accessTokenKey(for: evilEntry.id)))
        XCTAssertNil(keychain.get("com.continuum.app.accessToken"))
        XCTAssertTrue(registry.entries.contains(where: { $0.id == homeId }))
        XCTAssertTrue(defaults.bool(forKey: "continuumServerRegistry.migrated.v1"))
        XCTAssertNil(defaults.string(forKey: "continuumServerRegistry.legacySourceUrl.v1"))
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
        registry.setProfileId("p-new", for: "new")
        registry.updateFetchedName(for: "new", fetchedName: "New Name")

        XCTAssertEqual(registry.entry(with: "new")?.profileId, "p-new")
        XCTAssertEqual(registry.entry(with: "new")?.fetchedName, "New Name")
        XCTAssertEqual(registry.sortedEntries.map(\.id), ["new", "old"])
        XCTAssertFalse(registry.hasActiveServer)
    }

    func testMigrateLegacyFallsBackToEntryOwningRekeyedTokens() {
        // No pinned URL and no serverUrl mirror — resolve origin from an
        // existing registry entry that already holds re-keyed tokens.
        let home = "https://home.example"
        let other = "https://other.example"
        let homeId = ServerRegistry.serverId(for: home)
        let otherId = ServerRegistry.serverId(for: other)
        let homeEntry = ServerEntry(
            id: homeId,
            url: home,
            fetchedName: "Home",
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 2)
        )
        let otherEntry = ServerEntry(
            id: otherId,
            url: other,
            fetchedName: "Other",
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1)
        )
        struct Wire: Codable {
            var activeServerId: String?
            var entries: [ServerEntry]
        }
        let wireData = try! JSONEncoder().encode(
            Wire(activeServerId: otherId, entries: [otherEntry, homeEntry])
        )
        defaults.set(wireData, forKey: "continuumServerRegistry.v1")
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        // Home already owns re-keyed access; a leftover legacy profile token
        // still needs migration onto that same host (match branch).
        XCTAssertTrue(keychain.set("ACCESS-HOME", for: TokenStore.accessTokenKey(for: homeId)))
        XCTAssertTrue(keychain.set("PROFILE-LEGACY", for: "com.continuum.app.profileToken"))

        let registry = makeRegistry()

        XCTAssertTrue(defaults.bool(forKey: "continuumServerRegistry.migrated.v1"))
        XCTAssertNil(defaults.string(forKey: "continuumServerRegistry.legacySourceUrl.v1"))
        XCTAssertNil(keychain.get("com.continuum.app.profileToken"))
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: homeId)), "ACCESS-HOME")
        XCTAssertEqual(keychain.get(TokenStore.profileTokenKey(for: homeId)), "PROFILE-LEGACY")
        XCTAssertNil(keychain.get(TokenStore.accessTokenKey(for: otherId)))
        XCTAssertNil(keychain.get(TokenStore.profileTokenKey(for: otherId)))
        XCTAssertTrue(registry.entries.contains(where: { $0.id == homeId }))
    }

    func testMigrateLegacyFallsBackToFirstEntryWhenNoTokenOwner() {
        // Legacy tokens remain, but no serverUrl / pin / matching re-keyed owner —
        // last resort is the first registry entry.
        let firstURL = "https://first.example"
        let secondURL = "https://second.example"
        let firstId = ServerRegistry.serverId(for: firstURL)
        let secondId = ServerRegistry.serverId(for: secondURL)
        let firstEntry = ServerEntry(
            id: firstId,
            url: firstURL,
            fetchedName: "First",
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1)
        )
        let secondEntry = ServerEntry(
            id: secondId,
            url: secondURL,
            fetchedName: "Second",
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 2)
        )
        struct Wire: Codable {
            var activeServerId: String?
            var entries: [ServerEntry]
        }
        let wireData = try! JSONEncoder().encode(
            Wire(activeServerId: secondId, entries: [firstEntry, secondEntry])
        )
        defaults.set(wireData, forKey: "continuumServerRegistry.v1")
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        XCTAssertTrue(keychain.set("ACCESS-LEGACY", for: "com.continuum.app.accessToken"))
        XCTAssertTrue(keychain.set("REFRESH-LEGACY", for: "com.continuum.app.refreshToken"))
        XCTAssertTrue(keychain.set("PROFILE-LEGACY", for: "com.continuum.app.profileToken"))

        let registry = makeRegistry()

        XCTAssertTrue(defaults.bool(forKey: "continuumServerRegistry.migrated.v1"))
        XCTAssertNil(defaults.string(forKey: "continuumServerRegistry.legacySourceUrl.v1"))
        XCTAssertNil(keychain.get("com.continuum.app.accessToken"))
        XCTAssertEqual(keychain.get(TokenStore.accessTokenKey(for: firstId)), "ACCESS-LEGACY")
        XCTAssertEqual(keychain.get(TokenStore.refreshTokenKey(for: firstId)), "REFRESH-LEGACY")
        XCTAssertEqual(keychain.get(TokenStore.profileTokenKey(for: firstId)), "PROFILE-LEGACY")
        XCTAssertNil(keychain.get(TokenStore.accessTokenKey(for: secondId)))
        XCTAssertTrue(registry.entries.contains(where: { $0.id == firstId }))
    }

    func testSwitchAwayDiscardsUnmigratedLegacyTokensPinnedToOtherHost() async {
        // Mid-migration: pinned legacy origin still holds fixed-name tokens,
        // but the registry already has a different active server. Switching
        // away must drop those accounts so they cannot bind to the wrong host.
        let home = "https://home.example"
        let other = "https://other.example"
        let homeId = ServerRegistry.serverId(for: home)
        let otherId = ServerRegistry.serverId(for: other)
        let homeEntry = ServerEntry(
            id: homeId,
            url: home,
            fetchedName: "Home",
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1)
        )
        let otherEntry = ServerEntry(
            id: otherId,
            url: other,
            fetchedName: "Other",
            profileId: nil,
            lastUsedAt: Date(timeIntervalSince1970: 2)
        )
        struct Wire: Codable {
            var activeServerId: String?
            var entries: [ServerEntry]
        }
        let wireData = try! JSONEncoder().encode(
            Wire(activeServerId: homeId, entries: [homeEntry, otherEntry])
        )
        defaults.set(wireData, forKey: "continuumServerRegistry.v1")
        defaults.set(home, forKey: "serverUrl")
        defaults.set(home, forKey: "continuumServerRegistry.legacySourceUrl.v1")
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        XCTAssertTrue(keychain.set("ACCESS-HOME", for: "com.continuum.app.accessToken"))
        XCTAssertTrue(keychain.set("REFRESH-HOME", for: "com.continuum.app.refreshToken"))
        XCTAssertTrue(keychain.set("PROFILE-HOME", for: "com.continuum.app.profileToken"))

        let registry = makeRegistry()
        // Init may complete migration if it can re-key; force the mid-migration
        // window the switchTo guard protects.
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        defaults.set(home, forKey: "continuumServerRegistry.legacySourceUrl.v1")
        XCTAssertTrue(keychain.set("ACCESS-HOME", for: "com.continuum.app.accessToken"))
        XCTAssertTrue(keychain.set("REFRESH-HOME", for: "com.continuum.app.refreshToken"))
        XCTAssertTrue(keychain.set("PROFILE-HOME", for: "com.continuum.app.profileToken"))

        await registry.switchTo(serverId: otherId)

        XCTAssertNil(keychain.get("com.continuum.app.accessToken"))
        XCTAssertNil(keychain.get("com.continuum.app.refreshToken"))
        XCTAssertNil(keychain.get("com.continuum.app.profileToken"))
        XCTAssertNil(defaults.string(forKey: "continuumServerRegistry.legacySourceUrl.v1"))
        XCTAssertEqual(registry.activeServerId, otherId)
    }

    func testSwitchToUnknownIdIsNoOp() async {
        let registry = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://only.example")
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://only.example",
            fetchedName: "Only",
            profileId: "p1",
            lastUsedAt: Date()
        ))
        await registry.switchTo(serverId: id)
        XCTAssertEqual(registry.activeServerId, id)
        XCTAssertEqual(registry.activeServerUrl, "https://only.example")
        XCTAssertEqual(registry.activeProfileId, "p1")
        XCTAssertTrue(registry.hasActiveServer)

        await registry.switchTo(serverId: "missing-id")
        XCTAssertEqual(registry.activeServerId, id)
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
        XCTAssertNil(registry.entry(with: id)?.profileId)
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Home")

        registry.updateFetchedName(for: id, fetchedName: "")
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Home")
        registry.updateFetchedName(for: "missing", fetchedName: "Nope")
        registry.setProfileId("x", for: "missing")
    }

    func testSignOutClearsProfileAndTokens() async {
        // Token deletion goes through TokenStore.shared (process keychain), while
        // this suite injects an in-memory SharedKeychain into ServerRegistry only.
        // Assert registry/UserDefaults side effects here; TokenStore itself is
        // covered by TokenStoreTests.
        let registry = makeRegistry()
        let a = ServerRegistry.serverId(for: "https://a.example")
        let b = ServerRegistry.serverId(for: "https://b.example")
        registry.addOrUpdate(ServerEntry(
            id: a, url: "https://a.example", fetchedName: "A",
            profileId: "pa", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: b, url: "https://b.example", fetchedName: "B",
            profileId: "pb", lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        await registry.switchTo(serverId: a)
        XCTAssertEqual(defaults.string(forKey: "profileId"), "pa")

        await registry.signOut(serverId: a, purgeCurrentBinding: false)
        XCTAssertNil(registry.entry(with: a)?.profileId)
        XCTAssertNil(defaults.string(forKey: "profileId"))
        XCTAssertEqual(registry.activeServerId, a, "signOut keeps the entry and active slot")

        await registry.signOut(serverId: b, purgeCurrentBinding: true)
        XCTAssertNil(registry.entry(with: b)?.profileId)
    }

    func testSignOutDiscardsPinnedLegacyWhenHostMatches() async {
        let home = "https://home.example"
        let homeId = ServerRegistry.serverId(for: home)
        let entry = ServerEntry(
            id: homeId, url: home, fetchedName: "Home",
            profileId: "p", lastUsedAt: Date()
        )
        struct Wire: Codable {
            var activeServerId: String?
            var entries: [ServerEntry]
        }
        defaults.set(
            try! JSONEncoder().encode(Wire(activeServerId: homeId, entries: [entry])),
            forKey: "continuumServerRegistry.v1"
        )
        defaults.set(home, forKey: "serverUrl")
        defaults.set("p", forKey: "profileId")
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        defaults.set(home, forKey: "continuumServerRegistry.legacySourceUrl.v1")
        XCTAssertTrue(keychain.set("LEGACY", for: "com.continuum.app.accessToken"))

        let registry = makeRegistry()
        // Force mid-migration window after init may have completed re-key.
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        defaults.set(home, forKey: "continuumServerRegistry.legacySourceUrl.v1")
        XCTAssertTrue(keychain.set("LEGACY", for: "com.continuum.app.accessToken"))

        await registry.signOut(serverId: homeId, purgeCurrentBinding: false)
        XCTAssertNil(keychain.get("com.continuum.app.accessToken"))
        XCTAssertNil(defaults.string(forKey: "continuumServerRegistry.legacySourceUrl.v1"))
    }

    func testRemoveActiveFallsBackToMostRecentlyUsed() async {
        let registry = makeRegistry()
        let older = ServerRegistry.serverId(for: "https://old.example")
        let newer = ServerRegistry.serverId(for: "https://new.example")
        registry.addOrUpdate(ServerEntry(
            id: older, url: "https://old.example", fetchedName: "Old",
            profileId: "p-old", lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        registry.addOrUpdate(ServerEntry(
            id: newer, url: "https://new.example", fetchedName: "New",
            profileId: "p-new", lastUsedAt: Date(timeIntervalSince1970: 100)
        ))
        await registry.switchTo(serverId: older)

        await registry.remove(serverId: older)

        XCTAssertNil(registry.entry(with: older))
        XCTAssertEqual(registry.activeServerId, newer)
        XCTAssertEqual(defaults.string(forKey: "serverUrl"), "https://new.example")
        XCTAssertEqual(defaults.string(forKey: "profileId"), "p-new")
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

    func testRemoveActiveFallbackWithoutProfileClearsProfileMirror() async {
        let registry = makeRegistry()
        let active = ServerRegistry.serverId(for: "https://active.example")
        let fallback = ServerRegistry.serverId(for: "https://fallback.example")
        registry.addOrUpdate(ServerEntry(
            id: active, url: "https://active.example", fetchedName: "Active",
            profileId: "pa", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: fallback, url: "https://fallback.example", fetchedName: "Fallback",
            profileId: nil, lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        await registry.switchTo(serverId: active)
        XCTAssertEqual(defaults.string(forKey: "profileId"), "pa")

        await registry.remove(serverId: active)

        XCTAssertEqual(registry.activeServerId, fallback)
        XCTAssertEqual(defaults.string(forKey: "serverUrl"), "https://fallback.example")
        XCTAssertNil(defaults.string(forKey: "profileId"))
    }

    func testLoadSeedsSuiteFromStandardFallback() {
        let id = ServerRegistry.serverId(for: "https://seed.example")
        let entry = ServerEntry(
            id: id,
            url: "https://seed.example",
            fetchedName: "Seed",
            profileId: "seed-p",
            lastUsedAt: Date(timeIntervalSince1970: 42)
        )
        struct Wire: Codable {
            var activeServerId: String?
            var entries: [ServerEntry]
        }
        let data = try! JSONEncoder().encode(Wire(activeServerId: id, entries: [entry]))
        // Only standard has the registry blob — suite is empty so load()
        // must re-persist for Top Shelf / App Group consumers.
        standard.set(data, forKey: "continuumServerRegistry.v1")
        standard.set(true, forKey: "continuumServerRegistry.migrated.v1")
        XCTAssertNil(suite.data(forKey: "continuumServerRegistry.v1"))

        let registry = makeRegistry()
        XCTAssertEqual(registry.activeServerId, id)
        // Registry payload no longer owns the active profile mirror; without a
        // remembered launch mapping / AuthService write it stays unset.
        XCTAssertNil(registry.activeProfileId)
        XCTAssertNotNil(suite.data(forKey: "continuumServerRegistry.v1"))
        XCTAssertEqual(defaults.string(forKey: SharedStorage.serverUrlKey), "https://seed.example")
        XCTAssertNil(defaults.string(forKey: SharedStorage.profileIdKey))
    }

    func testLoadCorruptRegistryStartsEmpty() {
        standard.set(Data("not-json".utf8), forKey: "continuumServerRegistry.v1")
        standard.set(true, forKey: "continuumServerRegistry.migrated.v1")
        let registry = makeRegistry()
        XCTAssertTrue(registry.entries.isEmpty)
        XCTAssertNil(registry.activeServerId)
    }

    func testDiscardLegacyNoOpWhenAlreadyMigrated() {
        defaults.set(true, forKey: "continuumServerRegistry.migrated.v1")
        XCTAssertTrue(keychain.set("KEEP", for: "com.continuum.app.accessToken"))
        let registry = makeRegistry()
        registry.discardLegacyKeychainAccountsIfUnmigrated()
        XCTAssertEqual(keychain.get("com.continuum.app.accessToken"), "KEEP")
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

    func testSwitchToClearsProfileMirrorWhenEntryHasNone() async {
        let registry = makeRegistry()
        let withProfile = ServerRegistry.serverId(for: "https://with.example")
        let without = ServerRegistry.serverId(for: "https://without.example")
        registry.addOrUpdate(ServerEntry(
            id: withProfile, url: "https://with.example", fetchedName: "With",
            profileId: "p", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: without, url: "https://without.example", fetchedName: "Without",
            profileId: nil, lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        await registry.switchTo(serverId: withProfile)
        XCTAssertEqual(defaults.string(forKey: "profileId"), "p")
        await registry.switchTo(serverId: without)
        XCTAssertNil(defaults.string(forKey: "profileId"))
        XCTAssertEqual(registry.activeServerUrl, "https://without.example")
    }
}
