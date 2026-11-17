import Foundation
import XCTest
@testable import Prairie

/// ServerRegistry paths the other registry tests leave unrun: merging a
/// proven duplicate server (including the active one, a failed save, a failed
/// account commit and downloads that cannot move), the unanswered duplicate
/// proof, a removal refused under the identity transition, a switch whose
/// target was removed while it waited for the transition, and the legacy
/// profile and single-server migrations when storage refuses a write.
@MainActor
final class NetworkingRegistryRacesGateFillTests: XCTestCase {
    private static let proofsKey = "serverMerge.proofs.v1"

    private final class Flag { var ok = true }

    /// The same shape builds before the profile split saved (see
    /// ServerRegistryEdgeTests).
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

    /// The stored proof's JSON shape (`ServerMerge.Proof` is private).
    private struct StoredProof: Codable {
        let outcome: String
        let epochs: [String: UUID]
        let provenAt: Date
    }

    private struct World {
        let registry: ServerRegistry
        let defaults: SharedDefaults
        let home: ServerEntry
        let lan: ServerEntry
        let lanAccount: Account
    }

    private var names: [String] = []
    private var keychain: SharedKeychain!
    private var savedProofs: Data?
    private var downloadServerIds: [String] = []

    override func setUp() {
        super.setUp()
        names = []
        downloadServerIds = []
        keychain = .inMemory(service: "NetworkingRegistryRacesGateFillTests.\(UUID().uuidString)")
        savedProofs = SharedDefaults.shared.data(forKey: Self.proofsKey)
    }

    override func tearDown() {
        for name in names { UserDefaults().removePersistentDomain(forName: name) }
        names = []
        let root = DownloadFilePaths.rootDirectory()
        for id in downloadServerIds {
            try? FileManager.default.removeItem(at: DownloadFilePaths.serverPath(serverId: id, root: root))
        }
        downloadServerIds = []
        if let savedProofs {
            SharedDefaults.shared.set(savedProofs, forKey: Self.proofsKey)
        } else {
            SharedDefaults.shared.removeObject(forKey: Self.proofsKey)
        }
        savedProofs = nil
        keychain = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func suite() -> SharedDefaults {
        let name = "NetworkingRegistryRacesGateFillTests.\(UUID().uuidString)"
        names.append(name)
        let defaults = UserDefaults(suiteName: name)!
        return SharedDefaults(suite: defaults, standard: defaults)
    }

    private func tag() -> String {
        "rr" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    private func entry(_ url: String) -> ServerEntry {
        ServerEntry(id: ServerRegistry.serverId(for: url), url: url, fetchedName: nil, lastUsedAt: Date())
    }

    private func registry(defaults: SharedDefaults, accounts: AccountStore? = nil, persist: Flag? = nil,
                          prefs: ProfileLaunchPreferences? = nil, http: HTTPClient? = nil) -> ServerRegistry {
        var override: (([ServerEntry], String?) -> Bool)?
        if let persist {
            override = { _, _ in persist.ok }
        }
        return ServerRegistry(
            defaults: defaults,
            keychain: keychain,
            accounts: accounts,
            launchPreferences: prefs ?? ProfileLaunchPreferences(defaults: defaults),
            persistenceOverride: override,
            tokenStore: TokenStore(keychain: keychain, defaults: defaults),
            httpClient: http ?? HTTPClient(session: StubURLProtocol.Handler().makeSession()),
            unregisterPush: { _ in },
            restorePush: { _ in }
        )
    }

    /// Two saved addresses of one server, an `https` one and an active
    /// `http` one, each with its own signed-in user and a stored proof that
    /// they reach one backend. Merging drops the active `http` entry.
    private func makeWorld(persist: Flag? = nil) async throws -> World {
        let shared = suite()
        let store = AccountStore(keychain: keychain, defaults: shared)
        let reg = registry(defaults: shared, accounts: store, persist: persist)
        let t = tag()
        let home = entry("https://\(t).example")
        let lan = entry("http://\(t)-lan.example")
        downloadServerIds.append(home.id)
        downloadServerIds.append(lan.id)
        XCTAssertNotNil(reg.addOrUpdate(home))
        XCTAssertNotNil(reg.addOrUpdate(lan))
        XCTAssertTrue(reg.updateVerifiedServerId(for: home.id, verifiedServerId: "srv-\(t)"))
        XCTAssertTrue(reg.updateVerifiedServerId(for: lan.id, verifiedServerId: "srv-\(t)"))
        _ = try store.saveSignIn(serverId: home.id, origin: home.url, serverUserId: "u-home", username: nil,
                                 accessToken: "a-home", refreshToken: "r-home", replacingOtherAccounts: false)
        _ = try store.saveSignIn(serverId: lan.id, origin: lan.url, serverUserId: "u-lan", username: nil,
                                 accessToken: "a-lan", refreshToken: "r-lan", replacingOtherAccounts: false)
        let homeAccount = try XCTUnwrap(store.accounts(onServer: home.id).first)
        let lanAccount = try XCTUnwrap(store.accounts(onServer: lan.id).first)
        let homeEpoch = try XCTUnwrap(homeAccount.epoch)
        let lanEpoch = try XCTUnwrap(lanAccount.epoch)
        let proofs = [ServerMerge.pairKey(lan.id, home.id): StoredProof(
            outcome: "proven",
            epochs: [lanAccount.localAccountId: lanEpoch, homeAccount.localAccountId: homeEpoch],
            provenAt: Date()
        )]
        SharedDefaults.shared.set(try JSONEncoder().encode(proofs), forKey: Self.proofsKey)
        let switched = await reg.switchTo(serverId: lan.id)
        XCTAssertTrue(switched)
        XCTAssertEqual(reg.activeServerId, lan.id)
        return World(registry: reg, defaults: shared, home: home, lan: lan, lanAccount: lanAccount)
    }

    private func waitForPending(_ http: HTTPClient, count: Int) async {
        for _ in 0..<2000 {
            if await http.pendingIdentityTransitionCount() >= count { return }
            await Task.yield()
        }
        XCTFail("the identity transition never queued")
    }

    private func legacyState(_ item: ServerEntry, profileId: String?) throws -> Data {
        try JSONEncoder().encode(LegacyRegistryState(activeServerId: nil, entries: [
            LegacyServerEntry(id: item.id, url: item.url, fetchedName: nil, profileId: profileId,
                              lastUsedAt: item.lastUsedAt),
        ]))
    }

    // MARK: - Merging duplicate servers

    func testMergeMovesTheActiveEntryOntoTheHttpsSurvivor() async throws {
        let world = try await makeWorld()

        let survivors = world.registry.mergeDuplicateServers()

        XCTAssertEqual(survivors, [world.lan.id: world.home.id])
        XCTAssertNil(world.registry.entry(with: world.lan.id))
        XCTAssertNotNil(world.registry.entry(with: world.home.id))
        XCTAssertEqual(world.registry.activeServerId, world.home.id)
        XCTAssertEqual(world.defaults.string(forKey: SharedStorage.serverUrlKey), world.home.url)
        XCTAssertEqual(world.defaults.string(forKey: SharedStorage.activeServerIdKey), world.home.id)
    }

    func testMergeRollsBackWhenTheRegistryCannotBeSaved() async throws {
        let flag = Flag()
        let world = try await makeWorld(persist: flag)
        flag.ok = false

        let survivors = world.registry.mergeDuplicateServers()

        XCTAssertTrue(survivors.isEmpty)
        XCTAssertNotNil(world.registry.entry(with: world.lan.id))
        XCTAssertNotNil(world.registry.entry(with: world.home.id))
        XCTAssertEqual(world.registry.activeServerId, world.lan.id)
        XCTAssertEqual(world.defaults.string(forKey: SharedStorage.serverUrlKey), world.lan.url)
        XCTAssertEqual(world.defaults.string(forKey: SharedStorage.activeServerIdKey), world.lan.id)
    }

    func testMergeKeepsBothEntriesWhenTheAccountsCannotBeCommitted() async throws {
        let world = try await makeWorld()
        let store = try XCTUnwrap(keychain.memoryStore)
        store.failWrites = true
        defer { store.failWrites = false }

        let survivors = world.registry.mergeDuplicateServers()

        XCTAssertTrue(survivors.isEmpty)
        XCTAssertNotNil(world.registry.entry(with: world.lan.id))
        XCTAssertNotNil(world.registry.entry(with: world.home.id))
        XCTAssertEqual(world.registry.activeServerId, world.lan.id)
    }

    func testMergeWaitsWhenDownloadsCannotBeMoved() async throws {
        let world = try await makeWorld()
        let root = DownloadFilePaths.rootDirectory()
        let account = world.lanAccount.localAccountId
        let source = DownloadFilePaths.accountPath(serverId: world.lan.id, localAccountId: account, root: root)
        let target = DownloadFilePaths.accountPath(serverId: world.home.id, localAccountId: account, root: root)
        for directory in [source, target] {
            let scope = directory.appendingPathComponent("default")
            try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: scope.appendingPathComponent(DownloadFilePaths.storeFileName))
        }

        let survivors = world.registry.mergeDuplicateServers()

        XCTAssertTrue(survivors.isEmpty)
        XCTAssertNotNil(world.registry.entry(with: world.lan.id))
        XCTAssertEqual(world.registry.activeServerId, world.lan.id)
    }

    // MARK: - Duplicate server proof

    func testUnansweredProofIsAskedOnlyOncePerSessionSet() async throws {
        let shared = suite()
        let first = registry(defaults: shared)
        let t = tag()
        let home = entry("https://\(t).example")
        let alias = entry("https://\(t)-alias.example")
        XCTAssertNotNil(first.addOrUpdate(home))
        XCTAssertNotNil(first.addOrUpdate(alias))
        XCTAssertTrue(first.updateVerifiedServerId(for: home.id, verifiedServerId: "srv-\(t)"))
        XCTAssertTrue(first.updateVerifiedServerId(for: alias.id, verifiedServerId: "srv-\(t)"))

        // A launch that finds two entries reporting one server but no stored
        // answer and no user signed in at both addresses.
        let second = registry(defaults: shared)
        for _ in 0..<20 { await Task.yield() }
        second.scheduleDuplicateServerProof()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(second.entries.count, 2, "an unanswered proof merges nothing")
    }

    // MARK: - Switching and removing under the identity transition

    func testRemovalIsRefusedWhenTheCallerNoLongerWantsIt() async {
        let shared = suite()
        let reg = registry(defaults: shared)
        let item = entry("https://\(tag()).example")
        XCTAssertNotNil(reg.addOrUpdate(item))

        let removed = await reg.remove(serverId: item.id, onlyIf: { false })

        XCTAssertFalse(removed)
        XCTAssertNotNil(reg.entry(with: item.id))
    }

    func testSwitchFailsWhenItsTargetIsRemovedWhileItWaitsForTheTransition() async throws {
        let shared = suite()
        let http = HTTPClient(session: StubURLProtocol.Handler().makeSession())
        let reg = registry(defaults: shared, http: http)
        let t = tag()
        let keep = entry("https://\(t).example")
        let target = entry("https://\(t)-target.example")
        XCTAssertNotNil(reg.addOrUpdate(keep))
        XCTAssertNotNil(reg.addOrUpdate(target))

        let heldLease = await http.beginIdentityTransition()
        let held = try XCTUnwrap(heldLease)
        let removing = Task { @MainActor in await reg.remove(serverId: target.id) }
        await waitForPending(http, count: 1)
        let switching = Task { @MainActor in await reg.switchTo(serverId: target.id) }
        await waitForPending(http, count: 2)
        await http.endIdentityTransition(held)
        let removed = await removing.value
        let switched = await switching.value

        XCTAssertTrue(removed)
        XCTAssertFalse(switched)
        XCTAssertNil(reg.entry(with: target.id))
        XCTAssertNotEqual(reg.activeServerId, target.id)
    }

    // MARK: - Legacy profile mapping migration

    func testSignedOutLegacyProfileStaysWhenTheRegistryCannotBeSaved() throws {
        let shared = suite()
        let item = entry("https://\(tag()).example")
        shared.set(try legacyState(item, profileId: "p-out"), forKey: ServerRegistry.defaultsKey)
        let flag = Flag()
        flag.ok = false

        let reg = registry(defaults: shared, persist: flag)

        XCTAssertEqual(reg.entry(with: item.id)?.legacyProfileId, "p-out")
    }

    func testLegacyProfileStaysWhenTheAccountEpochCannotBeWritten() throws {
        let shared = suite()
        let item = entry("https://\(tag()).example")
        shared.set(try legacyState(item, profileId: "p-in"), forKey: ServerRegistry.defaultsKey)
        let accountKeychain = keychain.withAudience(.userIndependent)
        XCTAssertTrue(accountKeychain.set("access", for: SharedStorage.accessTokenAccount(for: item.id)))
        let store = try XCTUnwrap(keychain.memoryStore)
        store.failWrites = true
        defer { store.failWrites = false }

        let reg = registry(defaults: shared)

        XCTAssertEqual(reg.entry(with: item.id)?.legacyProfileId, "p-in")
    }

    func testLegacyProfileMovesUnderTheExistingAccountEpoch() throws {
        let shared = suite()
        let item = entry("https://\(tag()).example")
        shared.set(try legacyState(item, profileId: "p-in"), forKey: ServerRegistry.defaultsKey)
        let accountKeychain = keychain.withAudience(.userIndependent)
        XCTAssertTrue(accountKeychain.set("access", for: SharedStorage.accessTokenAccount(for: item.id)))
        XCTAssertTrue(accountKeychain.set(UUID().uuidString, for: SharedStorage.accountEpochAccount(for: item.id)))

        let reg = registry(defaults: shared)

        XCTAssertNotNil(reg.entry(with: item.id))
        XCTAssertNil(reg.entry(with: item.id)?.legacyProfileId, "the profile moved into the launch store")
    }

    func testLegacyProfileStaysWhenTheLaunchStoreCannotSaveIt() throws {
        let shared = suite()
        let item = entry("https://\(tag()).example")
        shared.set(try legacyState(item, profileId: "p-in"), forKey: ServerRegistry.defaultsKey)
        let accountKeychain = keychain.withAudience(.userIndependent)
        XCTAssertTrue(accountKeychain.set("access", for: SharedStorage.accessTokenAccount(for: item.id)))
        XCTAssertTrue(accountKeychain.set(UUID().uuidString, for: SharedStorage.accountEpochAccount(for: item.id)))
        let refusing = ProfileLaunchPreferences(defaults: shared, persistenceOverride: { _ in false })

        let reg = registry(defaults: shared, prefs: refusing)

        XCTAssertEqual(reg.entry(with: item.id)?.legacyProfileId, "p-in")
    }

    func testLegacyProfileIsRestoredWhenTheMigratedRegistryCannotBeSaved() throws {
        let shared = suite()
        let item = entry("https://\(tag()).example")
        shared.set(try legacyState(item, profileId: "p-in"), forKey: ServerRegistry.defaultsKey)
        let accountKeychain = keychain.withAudience(.userIndependent)
        XCTAssertTrue(accountKeychain.set("access", for: SharedStorage.accessTokenAccount(for: item.id)))
        XCTAssertTrue(accountKeychain.set(UUID().uuidString, for: SharedStorage.accountEpochAccount(for: item.id)))
        let flag = Flag()
        flag.ok = false

        let reg = registry(defaults: shared, persist: flag)

        XCTAssertEqual(reg.entry(with: item.id)?.legacyProfileId, "p-in")
    }

    // MARK: - Legacy single-server migration

    func testLegacyServerUrlIsNormalizedInPlace() {
        let shared = suite()
        let raw = "https://\(tag()).example/"
        shared.set("  \(raw)  ", forKey: SharedStorage.serverUrlKey)

        let reg = registry(defaults: shared)

        let normalized = ServerRegistry.normalize(url: raw)
        XCTAssertNotEqual(normalized, raw)
        XCTAssertEqual(reg.entries.count, 1)
        XCTAssertEqual(reg.entries.first?.url, normalized)
        XCTAssertEqual(reg.activeServerId, reg.entries.first?.id)
        XCTAssertEqual(shared.string(forKey: SharedStorage.serverUrlKey), normalized)
    }

    func testLegacyServerMigrationIsAbandonedWhenTheRegistryCannotBeSaved() {
        let shared = suite()
        shared.set("https://\(tag()).example", forKey: SharedStorage.serverUrlKey)
        let flag = Flag()
        flag.ok = false

        let reg = registry(defaults: shared, persist: flag)

        XCTAssertTrue(reg.entries.isEmpty)
        XCTAssertNil(reg.activeServerId)
    }
}
