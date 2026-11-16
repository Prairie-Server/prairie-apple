import Foundation
import XCTest
@testable import Prairie

/// ServerRegistry edges after the sync: verified identities, persistence
/// failures, cancelled switches and removals, a removal whose session cannot
/// be invalidated, seeding the shared suite, and moving legacy per-entry
/// profiles into the launch store.
@MainActor
final class ServerRegistryEdgeTests: XCTestCase {
    private final class Flag { var ok = true }

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

    private var names: [String] = []
    private var keychain: SharedKeychain!

    override func setUp() {
        super.setUp()
        keychain = .inMemory(service: "ServerRegistryEdgeTests.\(UUID().uuidString)")
    }

    override func tearDown() {
        for name in names { UserDefaults().removePersistentDomain(forName: name) }
        names = []
        keychain = nil
        super.tearDown()
    }

    private func suite() -> UserDefaults {
        let name = "ServerRegistryEdgeTests.\(UUID().uuidString)"
        names.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func registry(defaults: SharedDefaults, persist: Flag? = nil,
                          tokenStore: TokenStore? = nil) -> ServerRegistry {
        var override: (([ServerEntry], String?) -> Bool)?
        if let persist {
            override = { _, _ in persist.ok }
        }
        return ServerRegistry(
            defaults: defaults,
            keychain: keychain,
            launchPreferences: ProfileLaunchPreferences(defaults: defaults),
            persistenceOverride: override,
            tokenStore: tokenStore ?? TokenStore(keychain: keychain, defaults: defaults),
            httpClient: HTTPClient(session: StubURLProtocol.Handler().makeSession())
        )
    }

    private func entry(_ url: String) -> ServerEntry {
        ServerEntry(id: ServerRegistry.serverId(for: url), url: url, fetchedName: nil,
                    lastUsedAt: Date())
    }

    func testEmptyRegistryHasNoActiveServer() {
        let shared = SharedDefaults(suite: suite(), standard: suite())
        let empty = registry(defaults: shared)
        XCTAssertNil(empty.activeServer)
        XCTAssertEqual(empty.activeServerUrl, "")
        XCTAssertFalse(empty.hasActiveServer)
        XCTAssertNil(empty.activeProfileId)
    }

    func testVerifiedIdentityUpdatesAndLookups() {
        let flag = Flag()
        let registry = registry(defaults: SharedDefaults(suite: suite(), standard: suite()), persist: flag)
        let home = entry("https://home.example")
        registry.addOrUpdate(home)

        XCTAssertFalse(registry.updateVerifiedServerId(for: "missing", verifiedServerId: "srv-1"))
        XCTAssertFalse(registry.updateVerifiedServerId(for: home.id, verifiedServerId: "  "))
        XCTAssertTrue(registry.updateVerifiedServerId(for: home.id, verifiedServerId: " srv-1 "))
        XCTAssertTrue(registry.updateVerifiedServerId(for: home.id, verifiedServerId: "srv-1"), "unchanged is a success")
        XCTAssertEqual(registry.entry(verifiedServerId: "srv-1")?.id, home.id)
        XCTAssertNil(registry.entry(verifiedServerId: nil))
        XCTAssertNil(registry.entry(verifiedServerId: "srv-other"))

        flag.ok = false
        XCTAssertFalse(registry.updateVerifiedServerId(for: home.id, verifiedServerId: "srv-2"))
        XCTAssertEqual(registry.entry(with: home.id)?.verifiedServerId, "srv-1", "a failed save rolls back")
    }

    func testCancelledSwitchAndRemovalDoNothing() async {
        let registry = registry(defaults: SharedDefaults(suite: suite(), standard: suite()))
        let home = entry("https://home.example")
        registry.addOrUpdate(home)

        let unknown = await registry.switchTo(serverId: "missing")
        XCTAssertFalse(unknown)

        let switching = Task { await registry.switchTo(serverId: home.id) }
        switching.cancel()
        let switched = await switching.value
        XCTAssertFalse(switched)
        XCTAssertNil(registry.activeServerId)

        let removing = Task { await registry.remove(serverId: home.id) }
        removing.cancel()
        let removed = await removing.value
        XCTAssertFalse(removed)
        XCTAssertNotNil(registry.entry(with: home.id))
    }

    // tvOS keeps the registry in the shared Keychain instead of the suite.
    #if !os(tvOS)
    func testLoadSeedsTheSharedSuiteFromTheStandardFallback() async throws {
        let firstSuite = suite()
        let first = registry(defaults: SharedDefaults(suite: firstSuite, standard: firstSuite))
        let home = entry("https://seed.example")
        first.addOrUpdate(home)
        let switched = await first.switchTo(serverId: home.id)
        XCTAssertTrue(switched)
        let data = try XCTUnwrap(firstSuite.data(forKey: ServerRegistry.defaultsKey))

        let emptySuite = suite()
        let standard = suite()
        standard.set(data, forKey: ServerRegistry.defaultsKey)
        standard.set(true, forKey: ServerRegistry.migratedKey)
        let seeded = registry(defaults: SharedDefaults(suite: emptySuite, standard: standard))
        XCTAssertEqual(seeded.activeServerId, home.id)
        XCTAssertNotNil(emptySuite.data(forKey: ServerRegistry.defaultsKey))
        XCTAssertEqual(emptySuite.string(forKey: SharedStorage.serverUrlKey), "https://seed.example")
    }
    #endif

    func testExistingEntriesMarkTheLegacyMigrationDone() {
        let shared = SharedDefaults(suite: suite(), standard: suite())
        let first = registry(defaults: shared)
        first.addOrUpdate(entry("https://home.example"))
        shared.set(false, forKey: ServerRegistry.migratedKey)
        _ = registry(defaults: shared)
        XCTAssertTrue(shared.bool(forKey: ServerRegistry.migratedKey))
    }

    func testLegacyEntryProfilesMoveIntoTheLaunchStore() throws {
        let shared = SharedDefaults(suite: suite(), standard: suite())
        let signedOut = entry("https://signed-out.example")
        let signedIn = entry("https://signed-in.example")
        let legacy = LegacyRegistryState(activeServerId: nil, entries: [
            LegacyServerEntry(id: signedOut.id, url: signedOut.url, fetchedName: nil,
                              profileId: "p-out", lastUsedAt: signedOut.lastUsedAt),
            LegacyServerEntry(id: signedIn.id, url: signedIn.url, fetchedName: nil,
                              profileId: "p-in", lastUsedAt: signedIn.lastUsedAt),
        ])
        shared.set(try JSONEncoder().encode(legacy), forKey: ServerRegistry.defaultsKey)
        let accountKeychain = keychain.withAudience(.userIndependent)
        XCTAssertTrue(accountKeychain.set("access", for: SharedStorage.accessTokenAccount(for: signedIn.id)))

        let relaunched = registry(defaults: shared)
        XCTAssertNotNil(relaunched.entry(with: signedOut.id))
        XCTAssertNil(relaunched.entry(with: signedOut.id)?.legacyProfileId, "no account, so the profile is dropped")
        XCTAssertNil(relaunched.entry(with: signedIn.id)?.legacyProfileId, "moved into the launch store")
        XCTAssertNotNil(accountKeychain.get(SharedStorage.accountEpochAccount(for: signedIn.id)),
                        "the move binds the profile to a fresh account epoch")
    }
}
