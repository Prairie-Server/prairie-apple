import Foundation
import XCTest
@testable import Prairie

@MainActor
final class NetworkingPrefsCacheGateFillTests: XCTestCase {
    // MARK: Fixtures

    private static let standardKeys = ["AppleLanguages", "appLanguage.ledger.v1", "appLanguage.deviceList.v1"]
    private var savedStandardValues: [Any?] = []
    private var root: URL!

    private let shipped = ["en", "es", "fr", "ar"]
    private let profileA = HTTPRequestIdentity(serverId: "s", serverURL: "http://s", profileId: "A", clientFamily: "mobile")

    override func setUp() async throws {
        savedStandardValues = Self.standardKeys.map { UserDefaults.standard.object(forKey: $0) }
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkingPrefsCacheGateFillTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        for (key, value) in zip(Self.standardKeys, savedStandardValues) {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: AppLanguagePreferences

    func testDefaultRequestIdentityHasNoActiveProfile() async {
        let store = AppLanguagePreferences(
            transport: NetworkingPrefsCacheGateFillTransport(),
            system: NetworkingPrefsCacheGateFillSystem(),
            shipped: shipped
        )
        await store.refresh()
        XCTAssertNil(store.currentChoice)
        XCTAssertEqual(store.displayed, "en")
    }

    func testLocaleAndDirectionFollowTheDisplayedLanguage() {
        let rtlSystem = NetworkingPrefsCacheGateFillSystem()
        rtlSystem.deviceList = ["ar"]
        let rtl = AppLanguagePreferences(
            transport: NetworkingPrefsCacheGateFillTransport(),
            requestIdentity: { nil },
            system: rtlSystem,
            shipped: shipped
        )
        XCTAssertEqual(rtl.displayed, "ar")
        XCTAssertTrue(rtl.isRightToLeft)
        XCTAssertEqual(rtl.locale.language.languageCode?.identifier, "ar")
        XCTAssertFalse(rtl.isBusy)

        let ltr = AppLanguagePreferences(
            transport: NetworkingPrefsCacheGateFillTransport(),
            requestIdentity: { nil },
            system: NetworkingPrefsCacheGateFillSystem(),
            shipped: shipped
        )
        XCTAssertFalse(ltr.isRightToLeft)
        XCTAssertEqual(ltr.locale.language.languageCode?.identifier, "en")
    }

    func testOptionIdentifiersAreTheTagsWithAnEmptyIdForMatchDevice() {
        let store = AppLanguagePreferences(
            transport: NetworkingPrefsCacheGateFillTransport(),
            requestIdentity: { nil },
            system: NetworkingPrefsCacheGateFillSystem(),
            shipped: shipped
        )
        let ids = store.options.map(\.id)
        XCTAssertEqual(ids.first, "")
        XCTAssertEqual(Set(ids.dropFirst()), Set(shipped))
    }

    func testFailedCapabilitiesProbeLeavesEverythingAlone() async {
        let transport = NetworkingPrefsCacheGateFillTransport()
        transport.capabilities = .failed(.transport(description: "offline"))
        let identity = profileA
        let store = AppLanguagePreferences(
            transport: transport,
            requestIdentity: { identity },
            system: NetworkingPrefsCacheGateFillSystem(),
            shipped: shipped
        )

        await store.refresh()
        XCTAssertNil(store.currentChoice)
        XCTAssertEqual(store.displayed, "en")
        XCTAssertEqual(transport.effectiveReads, 0)
        XCTAssertEqual(transport.putCount, 0)
    }

    func testSystemChangeDuringTheReadBecomesThePendingChoice() async {
        let transport = NetworkingPrefsCacheGateFillTransport()
        let system = NetworkingPrefsCacheGateFillSystem()
        let identity = profileA
        let store = AppLanguagePreferences(
            transport: transport,
            requestIdentity: { identity },
            system: system,
            shipped: shipped
        )
        transport.effectiveHook = {
            system.appValue = ["fr"]
            system.ledger = AppLanguageLedger(applied: "es", baseline: nil)
        }

        await store.refresh()
        XCTAssertEqual(transport.effectiveReads, 1)
        // The read was abandoned: the server's value was not applied.
        XCTAssertNil(store.currentChoice)
        XCTAssertEqual(store.displayed, "en")
        XCTAssertEqual(transport.putCount, 0)
    }

    func testWriteFailureMessagesFollowTheErrorKind() {
        let unsupported = AppLanguage.string(.settingsAppLanguageSaveUnsupported)
        let generic = AppLanguage.string(.settingsAppLanguageSaveFailed)
        XCTAssertNotEqual(unsupported, generic)
        XCTAssertEqual(
            AppLanguage.string(AppLanguagePreferences.writeFailureMessage(for: SettingsAPIError.serverUpgradeRequired)),
            unsupported
        )
        XCTAssertEqual(
            AppLanguage.string(AppLanguagePreferences.writeFailureMessage(for: SettingsAPIError.invalidValue(message: "bad"))),
            generic
        )
    }

    // MARK: StandardAppLanguageSystem

    func testStandardSystemKeepsItsLedgerAndRecordsTheDeviceList() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "appLanguage.ledger.v1")
        let system = StandardAppLanguageSystem()
        XCTAssertNil(system.ledger)

        // Without a ledger the write records the device's own list first.
        let before = Locale.preferredLanguages
        system.write(.set(["es"]))
        XCTAssertEqual(defaults.stringArray(forKey: "appLanguage.deviceList.v1"), before)
        XCTAssertFalse(system.effectiveList.isEmpty)
        _ = system.appValue

        system.write(.remove)
        XCTAssertFalse(system.effectiveList.isEmpty)

        let ledger = AppLanguageLedger(applied: "es", baseline: ["fr"])
        system.ledger = ledger
        XCTAssertEqual(system.ledger, ledger)
        system.write(.remove)

        system.ledger = nil
        XCTAssertNil(system.ledger)
        XCTAssertNil(defaults.data(forKey: "appLanguage.ledger.v1"))

        system.storeDisplayed(AppLanguage.displayedTag ?? "en")
    }

    func testDeviceLanguagesReadsTheBaselineThenTheGlobalListThenTheRecordedOne() {
        let suiteName = "NetworkingPrefsCacheGateFillTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        // No ledger: the plain device list.
        XCTAssertEqual(
            StandardAppLanguageSystem.deviceLanguages(defaults: suite, global: ["de"]),
            Locale.preferredLanguages
        )

        // Whether Prairie's value counts as the app's own depends on the host's
        // bundle domain, so each case checks the branch the current state selects.
        UserDefaults.standard.set(["es"], forKey: "AppleLanguages")
        let owns = StandardAppLanguageSystem().appValue == ["es"]
        let fallback = Locale.preferredLanguages

        func store(_ ledger: AppLanguageLedger) {
            suite.set(try? JSONEncoder().encode(ledger), forKey: "appLanguage.ledger.v1")
        }

        store(AppLanguageLedger(applied: "es", baseline: ["fr"]))
        XCTAssertEqual(
            StandardAppLanguageSystem.deviceLanguages(defaults: suite, global: ["de"]),
            owns ? ["fr"] : fallback
        )

        store(AppLanguageLedger(applied: "es", baseline: nil))
        XCTAssertEqual(
            StandardAppLanguageSystem.deviceLanguages(defaults: suite, global: ["de"]),
            owns ? ["de"] : fallback
        )

        suite.set(["it"], forKey: "appLanguage.deviceList.v1")
        XCTAssertEqual(
            StandardAppLanguageSystem.deviceLanguages(defaults: suite, global: nil),
            owns ? ["it"] : fallback
        )
        XCTAssertEqual(
            StandardAppLanguageSystem.deviceLanguages(defaults: suite, global: []),
            owns ? ["it"] : fallback
        )

        suite.removeObject(forKey: "appLanguage.deviceList.v1")
        XCTAssertEqual(
            StandardAppLanguageSystem.deviceLanguages(defaults: suite, global: nil),
            owns ? [] : fallback
        )
    }

    // MARK: CurrentProfileStore

    func testConcurrentRefreshesShareOneRequest() async {
        let store = CurrentProfileStore()
        let first = Task { await store.refresh() }
        let second = Task { await store.refresh(force: true) }
        await first.value
        await second.value
        // The host's AuthService has no active profile, so nothing loads.
        XCTAssertNil(store.profile)
    }

    func testAdoptIgnoresAProfileThatIsNotTheActiveOne() {
        let store = CurrentProfileStore()
        store.adopt(UserProfile(id: "someone", name: "Someone", avatarEmoji: nil, hasPin: false, isChild: false))
        XCTAssertNil(store.profile)
        store.reset()
        XCTAssertNil(store.profile)
    }

    func testFreshProfileWinsWhenTheCachedAvatarImageIsGone() {
        func profile(id: String = "p1", emoji: String? = nil, url: String?) -> UserProfile {
            UserProfile(id: id, name: "Pat", avatarEmoji: emoji, avatarImageUrl: url, hasPin: false, isChild: false)
        }
        let cached = profile(url: "https://cdn.example/avatars/pat.webp?X-Amz-Signature=old")
        let fresh = profile(url: "https://cdn.example/avatars/pat.webp?X-Amz-Signature=new")

        // Nothing cached to keep.
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(fresh, from: nil), fresh)
        // A different profile.
        let other = profile(id: "p2", url: cached.avatarImageUrl)
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(fresh, from: other), fresh)
        // A different emoji.
        let emoji = profile(emoji: "x", url: cached.avatarImageUrl)
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(fresh, from: emoji), fresh)
        // No avatar URL on either side.
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(profile(url: nil), from: cached), profile(url: nil))
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(fresh, from: profile(url: nil)), fresh)
        // The same URL.
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(cached, from: cached), cached)
        // A different image object.
        let elsewhere = profile(url: "https://cdn.example/avatars/other.webp?X-Amz-Signature=new")
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(elsewhere, from: cached), elsewhere)
        // Same object under a new signature, but the host has no decoded-image cache.
        XCTAssertEqual(CurrentProfileStore.keepingCachedAvatar(fresh, from: cached), fresh)
    }

    // MARK: ResponseSnapshotStore

    private static let accountOne = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    private static let accountTwo = "7A9619FF-8B86-D011-B42D-00C04FC964FF"

    private func scope(_ server: String, _ account: String, _ profile: String) -> ResponseSnapshotStore.Scope {
        ResponseSnapshotStore.Scope(serverId: server, localAccountId: account, profileId: profile)
    }

    private func encodedName(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeLegacyDirectory(server: String, profile: String) throws -> URL {
        let directory = root.appendingPathComponent(encodedName("\(server)|\(profile)"), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(SectionsResponse(sections: []))
        try data.write(to: directory.appendingPathComponent(encodedName(CacheKey.homeSections) + ".json"))
        return directory
    }

    private func makeStrayDirectory() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("!!!not-base64", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func keys(_ scope: ResponseSnapshotStore.Scope) -> [String] {
        ResponseSnapshotStore.load(scope: scope, in: root).map(\.key).sorted()
    }

    private func storeSections(_ scope: ResponseSnapshotStore.Scope) {
        ResponseSnapshotStore.store(SectionsResponse(sections: []), forKey: CacheKey.homeSections, scope: scope, in: root)
    }

    func testRemovingFromAScopeThatWasNeverStoredIsHarmless() {
        ResponseSnapshotStore.remove(scope: scope("none", Self.accountOne, "p"), in: root) { _ in true }
        XCTAssertTrue(keys(scope("none", Self.accountOne, "p")).isEmpty)

        // A key too long for a file name is not saved at all.
        let tooLong = "browse:" + String(repeating: "a", count: 400)
        ResponseSnapshotStore.store(
            CatalogResponse(items: [], total: 0, totalExact: true, hasMore: false),
            forKey: tooLong, scope: scope("none", Self.accountOne, "p"), in: root
        )
        XCTAssertTrue(keys(scope("none", Self.accountOne, "p")).isEmpty)
    }

    func testRemoveAllOfAnAccountLeavesOtherAccountsAndServers() throws {
        let target = scope("server-a", Self.accountOne, "p1")
        let sibling = scope("server-a", Self.accountTwo, "p1")
        let otherServer = scope("server-b", Self.accountOne, "p1")
        for each in [target, sibling, otherServer] { storeSections(each) }
        XCTAssertEqual(keys(target), [CacheKey.homeSections])
        let legacy = try makeLegacyDirectory(server: "server-a", profile: "p1")
        try makeStrayDirectory()

        ResponseSnapshotStore.removeAll(ofAccount: Self.accountOne, onServer: "server-a", includingLegacy: false, in: root)
        XCTAssertTrue(keys(target).isEmpty)
        XCTAssertEqual(keys(sibling), [CacheKey.homeSections])
        XCTAssertEqual(keys(otherServer), [CacheKey.homeSections])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "from before accounts, kept unless asked")

        ResponseSnapshotStore.removeAll(ofAccount: Self.accountOne, onServer: "server-a", includingLegacy: true, in: root)
        // `load` waits for the queued removal.
        XCTAssertEqual(keys(sibling), [CacheKey.homeSections])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testAccountOperationsOnAMissingRootDoNothing() {
        ResponseSnapshotStore.removeAll(ofAccount: Self.accountOne, onServer: "server-a", includingLegacy: true, in: root)
        ResponseSnapshotStore.moveAll(
            fromServer: "old", toServer: "new", accounts: [Self.accountOne], legacyTarget: nil, in: root
        )
        XCTAssertTrue(keys(scope("new", Self.accountOne, "p1")).isEmpty)
    }

    func testMoveAllCarriesListedAccountsAndLegacyToTheSurvivor() throws {
        let moved = scope("old", Self.accountOne, "p1")
        let dropped = scope("old", Self.accountTwo, "p1")
        let conflictSource = scope("old", Self.accountOne, "p3")
        let conflictSurvivor = scope("new", Self.accountOne, "p3")
        let unrelated = scope("other", Self.accountOne, "p1")
        storeSections(moved)
        storeSections(dropped)
        ResponseSnapshotStore.store(
            LibrariesResponse(libraries: []), forKey: CacheKey.userLibraries, scope: conflictSource, in: root
        )
        storeSections(conflictSurvivor)
        storeSections(unrelated)
        XCTAssertEqual(keys(moved), [CacheKey.homeSections])
        _ = try makeLegacyDirectory(server: "old", profile: "p2")
        _ = try makeLegacyDirectory(server: "unrelated-legacy", profile: "p2")
        try makeStrayDirectory()

        ResponseSnapshotStore.moveAll(
            fromServer: "old", toServer: "new", accounts: [Self.accountOne], legacyTarget: Self.accountOne, in: root
        )

        XCTAssertEqual(keys(scope("new", Self.accountOne, "p1")), [CacheKey.homeSections])
        XCTAssertEqual(keys(scope("new", Self.accountOne, "p2")), [CacheKey.homeSections])
        XCTAssertEqual(keys(conflictSurvivor), [CacheKey.homeSections], "the survivor keeps its own")
        XCTAssertTrue(keys(moved).isEmpty)
        XCTAssertTrue(keys(dropped).isEmpty)
        XCTAssertTrue(keys(conflictSource).isEmpty)
        XCTAssertEqual(keys(unrelated), [CacheKey.homeSections])
        XCTAssertTrue(keys(scope("new", Self.accountTwo, "p1")).isEmpty)
    }

    func testMoveAllWithoutALegacyTargetDeletesTheLegacySnapshots() throws {
        let legacy = try makeLegacyDirectory(server: "old", profile: "p5")
        ResponseSnapshotStore.moveAll(
            fromServer: "old", toServer: "new", accounts: [], legacyTarget: nil, in: root
        )
        XCTAssertTrue(keys(scope("new", Self.accountOne, "p5")).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }
}

// MARK: - Fakes

@MainActor
private final class NetworkingPrefsCacheGateFillSystem: AppLanguageSystem {
    var appValue: [String]?
    var deviceList = ["en-US"]
    var ledger: AppLanguageLedger?
    private(set) var displayedStored: String?

    var effectiveList: [String] { appValue ?? deviceList }

    func write(_ write: AppLanguageReconciler.Write) {
        switch write {
        case .set(let tags): appValue = tags
        case .remove: appValue = nil
        }
    }

    func storeDisplayed(_ tag: String) { displayedStored = tag }
}

@MainActor
private final class NetworkingPrefsCacheGateFillTransport: TitleArtTransport, @unchecked Sendable {
    /// Nil answers as a server that has the language setting.
    var capabilities: SettingsCapabilitiesResult?
    /// Runs inside the next effective read, before it answers.
    var effectiveHook: (@MainActor () -> Void)?
    private(set) var effectiveReads = 0
    private(set) var putCount = 0

    nonisolated func contractCapabilities(requestIdentity: HTTPRequestIdentity) async -> SettingsCapabilitiesResult {
        await MainActor.run {
            capabilities ?? .available(APIv2SettingsContractCapabilities(
                revision: "capabilities-28",
                state: "available",
                allowed: true,
                manifestRevision: 28,
                clientFamilies: ["tv", "mobile", "tablet", "desktop", "web"],
                supportsBatchedEffective: true
            ))
        }
    }

    nonisolated func effectiveValues(
        keys: [SettingKey],
        requestIdentity: HTTPRequestIdentity
    ) async throws -> EffectiveSettingValuesResponse {
        try await MainActor.run {
            effectiveReads += 1
            let hook = effectiveHook
            effectiveHook = nil
            hook?()
            let row: [String: Any] = ["key": "ui.app_language", "value": NSNull(), "source": "default"]
            let data = try JSONSerialization.data(withJSONObject: ["items": [row], "revision": 28])
            return try SettingsWireCoding.makeDecoder().decode(EffectiveSettingValuesResponse.self, from: data)
        }
    }

    nonisolated func putValue(
        key: SettingKey,
        scope: SettingScopeIdentity,
        value: SettingJSONValue,
        requestIdentity: HTTPRequestIdentity
    ) async throws {
        await MainActor.run { putCount += 1 }
    }

    nonisolated func deleteValue(
        key: SettingKey,
        scope: SettingScopeIdentity,
        requestIdentity: HTTPRequestIdentity
    ) async throws {}
}
