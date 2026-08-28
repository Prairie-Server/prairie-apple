//
//  NetworkingSiloGateFillTests.swift
//  PrairieNetworkingTests
//
//  Closes coverage gaps the silo merge introduced: expanded TokenStore /
//  ServerRegistry surfaces, onboarding UserDefaults helpers, and model
//  members the existing gate-fill suites do not touch.
//

import XCTest
import Foundation
@testable import Prairie

final class NetworkingSiloGateFillTests: XCTestCase {

    // MARK: - OnboardingModels

    func testLegacyInviteTourSuppressionRoundTripAndUnsafeV1Clear() throws {
        let suiteName = "NetworkingSiloGateFill.legacyInvite.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let defaults = SharedDefaults(suite: suite, standard: suite)
        defer { suite.removePersistentDomain(forName: suiteName) }

        suite.set("unsafe", forKey: "onboardingTourSuppressedServerId.v1")
        XCTAssertNil(LegacyInviteTourSuppression.pendingUserId(for: "server-a", defaults: defaults))
        XCTAssertNil(suite.object(forKey: "onboardingTourSuppressedServerId.v1"))

        let record = try JSONSerialization.data(withJSONObject: [
            "serverId": "server-a",
            "userId": "user-a",
        ])
        defaults.set(record, forKey: "onboardingTourSuppressedAccount.v2")
        XCTAssertEqual(
            LegacyInviteTourSuppression.pendingUserId(for: "server-a", defaults: defaults),
            "user-a"
        )
        LegacyInviteTourSuppression.clear(serverId: "server-a", userId: "other", defaults: defaults)
        XCTAssertEqual(
            LegacyInviteTourSuppression.pendingUserId(for: "server-a", defaults: defaults),
            "user-a"
        )
        LegacyInviteTourSuppression.clear(serverId: "server-a", userId: "user-a", defaults: defaults)
        XCTAssertNil(LegacyInviteTourSuppression.pendingUserId(for: "server-a", defaults: defaults))
    }

    func testUnrenderableOnboardingTourSuppressionRoundTrip() {
        let serverId = "server-\(UUID().uuidString)"
        let profileId = "profile-a"
        let tourId = "tour-a"

        UnrenderableOnboardingTourSuppression.set(
            serverId: serverId,
            profileId: profileId,
            tourId: tourId
        )
        XCTAssertEqual(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: serverId,
                profileId: profileId
            ),
            tourId
        )
        XCTAssertNil(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: serverId,
                profileId: "other"
            )
        )
        UnrenderableOnboardingTourSuppression.clear(
            serverId: serverId,
            profileId: profileId,
            tourId: "wrong"
        )
        XCTAssertEqual(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: serverId,
                profileId: profileId
            ),
            tourId
        )
        UnrenderableOnboardingTourSuppression.clear(
            serverId: serverId,
            profileId: profileId,
            tourId: tourId
        )
        XCTAssertNil(
            UnrenderableOnboardingTourSuppression.pendingTourId(
                serverId: serverId,
                profileId: profileId
            )
        )
    }

    // MARK: - ServerRegistry identity helpers

    func testServerIdentityMatchesURLCapitalizationAcrossDevices() {
        let phone = ServerRegistry.serverId(for: "https://Media.Example.test")
        let tv = ServerRegistry.serverId(for: "HTTPS://media.example.test/")

        XCTAssertNotEqual(phone, tv, "persisted registry keys remain unchanged")
        XCTAssertTrue(ServerRegistry.serverIdsMatch(phone, tv))
    }

    func testServerIdentityMatchesDefaultPortsButNotDifferentOrigins() {
        let canonical = ServerRegistry.serverId(for: "https://media.example.test/library")
        let explicitDefault = ServerRegistry.serverId(for: "https://MEDIA.example.test:443/library/")
        let httpCanonical = ServerRegistry.serverId(for: "http://media.example.test/library")
        let httpExplicitDefault = ServerRegistry.serverId(for: "http://MEDIA.example.test:80/library/")
        let otherPort = ServerRegistry.serverId(for: "https://media.example.test:8443/library")
        let otherScheme = ServerRegistry.serverId(for: "http://media.example.test/library")
        let pathCase = ServerRegistry.serverId(for: "https://media.example.test/Library")

        XCTAssertTrue(ServerRegistry.serverIdsMatch(canonical, explicitDefault))
        XCTAssertTrue(ServerRegistry.serverIdsMatch(httpCanonical, httpExplicitDefault))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(canonical, otherPort))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(canonical, otherScheme))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(canonical, pathCase))
        XCTAssertNil(ServerRegistry.url(forServerId: ""))
    }

    func testServerIdentityDecoderRequiresAValidRoundTrippingHTTPURL() {
        let original = "https://Média.example.test:443/silo?mode=A#top"
        let serverId = ServerRegistry.serverId(for: original)

        XCTAssertEqual(ServerRegistry.url(forServerId: serverId), original)
        XCTAssertNil(ServerRegistry.url(forServerId: "not-a-registry-id"))
        XCTAssertNil(ServerRegistry.url(forServerId: ServerRegistry.serverId(for: "file:///tmp/silo")))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(nil, serverId))
        XCTAssertTrue(ServerRegistry.serverIdsMatch("future-format", "future-format"))
        XCTAssertFalse(ServerRegistry.serverIdsMatch("future-format-a", "future-format-b"))
    }

    func testServerRegistryErrorDescriptionAndSharedSnapshotReadable() {
        XCTAssertEqual(
            ServerRegistryError.persistenceFailed.errorDescription,
            "Prairie couldn't save the server list. Please try again."
        )
        _ = ServerRegistry.activeServerIDSnapshot
    }

    // MARK: - Models / settings helpers

    func testItemVideoAndExtraMemberwiseAndDecode() throws {
        let video = ItemVideo(
            kind: "trailer",
            site: "youtube",
            siteKey: "abc",
            name: "Official",
            language: "en",
            isOfficial: true
        )
        XCTAssertEqual(video.siteKey, "abc")

        let decoder = HTTPClient.makeJSONDecoder()
        let decodedVideo = try decoder.decode(ItemVideo.self, from: Data("""
        {
          "kind": "teaser",
          "site": "youtube",
          "site_key": "xyz",
          "name": "Teaser"
        }
        """.utf8))
        XCTAssertEqual(decodedVideo.siteKey, "xyz")
        XCTAssertFalse(decodedVideo.isOfficial)

        let extra = ItemExtra(
            contentId: "extra:1",
            kind: "featurette",
            title: "Behind",
            durationSeconds: 90,
            fileId: 7
        )
        XCTAssertEqual(extra.id, "extra:1")

        let decodedExtra = try decoder.decode(ItemExtra.self, from: Data("""
        {
          "content_id": "extra:2",
          "kind": "deleted_scene",
          "title": "Cut"
        }
        """.utf8))
        XCTAssertEqual(decodedExtra.id, "extra:2")
        XCTAssertNil(decodedExtra.fileId)
    }

    func testLibraryNavigationIconsAndSettingsContractHelpers() throws {
        let mixed = Library(
            id: 1,
            name: "Mixed",
            type: "mixed",
            sortOrder: nil,
            posterUrl: nil
        )
        let movies = Library(
            id: 2,
            name: "Movies",
            type: "movies",
            sortOrder: nil,
            posterUrl: nil
        )
        XCTAssertEqual(mixed.navigationIcon, "square.stack.3d.up")
        XCTAssertEqual(mixed.selectedNavigationIcon, "square.stack.3d.up.fill")
        XCTAssertEqual(movies.navigationIcon, "rectangle.stack")
        XCTAssertEqual(movies.selectedNavigationIcon, "rectangle.stack.fill")

        let caps = SettingsContractCapabilities(
            apiVersion: 1,
            revision: 5,
            contractEtag: "etag",
            definitionCount: 3,
            scopes: ["user"],
            supportsBatchedEffective: true,
            supportsIdempotentWrites: true,
            supportsAtomicShortcuts: true
        )
        XCTAssertTrue(caps.supportsUICustomizationRevision)
        XCTAssertFalse(
            SettingsContractCapabilities(
                apiVersion: 1,
                revision: 4,
                contractEtag: "etag",
                definitionCount: 1,
                scopes: [],
                supportsBatchedEffective: true,
                supportsIdempotentWrites: true,
                supportsAtomicShortcuts: true
            ).supportsUICustomizationRevision
        )

        let effective = EffectiveSettingValue(
            key: "playback.auto_play_next",
            value: true,
            source: .scope(.profile),
            storedValue: false,
            constrained: true,
            constraintKind: .ceiling,
            suggestedValues: ["true"],
            scope: .profile,
            profileId: "p1"
        )
        XCTAssertEqual(effective.storedAt?.scope, .profile)
        XCTAssertEqual(effective.profileId, "p1")

        let encodedSource = try SettingsWireCoding.makeEncoder().encode(SettingSource.contractDefault)
        XCTAssertEqual(
            try SettingsWireCoding.makeDecoder().decode(SettingSource.self, from: encodedSource),
            .contractDefault
        )
        let encodedScopeSource = try SettingsWireCoding.makeEncoder().encode(SettingSource.scope(.profileDevice))
        XCTAssertEqual(
            try SettingsWireCoding.makeDecoder().decode(SettingSource.self, from: encodedScopeSource),
            .scope(.profileDevice)
        )

        // Wrong-type accessors stay nil.
        XCTAssertNil(SettingJSONValue.string("x").boolValue)
        XCTAssertNil(SettingJSONValue.bool(true).stringValue)
        XCTAssertNil(SettingJSONValue.int(1).arrayValue)
        XCTAssertNil(SettingJSONValue.array([]).objectValue)

        let libraryScoped = EffectiveSettingValue(
            key: "playback.auto_play_next",
            value: true,
            source: .scope(.profileLibrary),
            scope: .profileLibrary,
            libraryId: 9
        )
        XCTAssertEqual(libraryScoped.storedAt, .profileLibrary(libraryId: 9))
        let seriesScoped = EffectiveSettingValue(
            key: "playback.auto_play_next",
            value: true,
            source: .scope(.profileSeries),
            scope: .profileSeries,
            seriesId: "series-1"
        )
        XCTAssertEqual(seriesScoped.storedAt, .profileSeries(seriesId: "series-1"))
        let unknownScoped = EffectiveSettingValue(
            key: "playback.auto_play_next",
            value: true,
            source: .scope(.other("future")),
            scope: .other("future")
        )
        XCTAssertNil(unknownScoped.storedAt)

        let trailerRefresh = try HTTPClient.makeJSONDecoder().decode(
            TrailerRefreshResponse.self,
            from: Data(#"{"status":"queued"}"#.utf8)
        )
        XCTAssertEqual(trailerRefresh.status, "queued")
        XCTAssertNil(trailerRefresh.nextAllowedAt)

        let subtitleURL = SubtitleUrl(
            index: 2,
            language: "en",
            codec: "subrip",
            label: "English",
            source: "embedded",
            forced: false,
            default: true,
            hearingImpaired: false,
            fontBundleUrl: nil,
            url: "https://example.invalid/sub.srt"
        )
        XCTAssertEqual(subtitleURL.id, 2)
        let search = SubtitleSearchResponse(results: [], warnings: ["none"])
        XCTAssertTrue(search.results.isEmpty)
        XCTAssertEqual(search.warnings, ["none"])
    }

    func testLibrariesResponseAcceptsBareArrayAndUnsupportedTypes() throws {
        let decoder = HTTPClient.makeJSONDecoder()
        let bare = try decoder.decode(
            LibrariesResponse.self,
            from: Data("""
            [
              {"id":1,"name":"Movies","type":"movies"},
              {"id":2,"name":"Weird","type":"unsupported-future"}
            ]
            """.utf8)
        )
        XCTAssertEqual(bare.libraries.map(\.id), [1])

        let wrapped = try decoder.decode(
            LibrariesResponse.self,
            from: Data("""
            {
              "libraries": [
                {"id":3,"name":"Shows","type":"series"},
                {"id":4,"name":"Skip","type":"nope"}
              ]
            }
            """.utf8)
        )
        XCTAssertEqual(wrapped.libraries.map(\.id), [3])
        XCTAssertEqual(
            LibrariesResponse(libraries: [
                Library(id: 9, name: "Mixed", type: "mixed", sortOrder: nil, posterUrl: nil),
                Library(id: 10, name: "Bad", type: "nope", sortOrder: nil, posterUrl: nil),
            ]).libraries.map(\.id),
            [9]
        )
    }

    func testAppUpdateDisplayVersionAndLiveTVAuthQueryHelpers() {
        _ = AppUpdateChecker.displayVersionString()
        _ = AppUpdateChecker.marketingVersionString()

        let hls = LiveTVSessionStartResponse(
            sessionId: "s1",
            playbackTicket: "ticket",
            hlsUrl: "https://live.example/index.m3u8",
            streamUrl: nil,
            transport: "mpegts",
            note: nil
        )
        XCTAssertTrue(hls.isHLS)
        XCTAssertEqual(hls.playableURLString, "https://live.example/index.m3u8")

        let fallback = LiveTVSessionStartResponse(
            sessionId: "s2",
            playbackTicket: "ticket",
            hlsUrl: "   ",
            streamUrl: "https://live.example/stream.ts",
            transport: "mpegts",
            note: nil
        )
        XCTAssertFalse(fallback.isHLS)
        XCTAssertEqual(fallback.playableURLString, "https://live.example/stream.ts")

        let resolved = LiveTVURLResolver.resolve(
            "/livetv/channels/1/stream",
            serverBaseURL: "https://live.example",
            accessToken: "tok",
            profileId: "prof"
        )
        XCTAssertEqual(resolved?.host, "live.example")
        XCTAssertTrue(resolved?.absoluteString.contains("tok") == true)
        XCTAssertTrue(resolved?.absoluteString.contains("prof") == true)
    }

    func testPlaybackLanguageOptionAliasReplacementAndIdentity() {
        let options = PlaybackLanguageOption.options(
            for: .playbackSubtitleLanguage,
            currentValue: "mao",
            runtimeValues: ["mi", "fre", " "]
        )
        XCTAssertFalse(options.isEmpty)
        XCTAssertTrue(options.contains(where: { $0.id == $0.code }))
        XCTAssertTrue(options.contains(where: { $0.code == "mao" || $0.code == "mi" }))
        XCTAssertFalse(options.contains(where: { $0.code.isEmpty }))
    }

    func testRequestMediaTypeIdAndCacheKeyCatalogFilters() {
        XCTAssertEqual(RequestMediaType.movie.id, RequestMediaType.movie)
        XCTAssertEqual(RequestMediaType.series.id, RequestMediaType.series)
        XCTAssertEqual(RequestMediaType.movie.displayName, "Movie")
        _ = CacheKey.catalogFilters(libraryId: 7, includeTechnical: true)
        _ = CacheKey.catalogFilters(libraryId: nil, includeTechnical: false)
        _ = AppUpdateChecker.displayVersionString()
    }
}

@MainActor
final class NetworkingSiloRegistryGateFillTests: XCTestCase {
    private var suiteName: String!
    private var standardName: String!
    private var suite: UserDefaults!
    private var standard: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!
    private var launchPreferences: ProfileLaunchPreferences!

    override func setUp() {
        super.setUp()
        suiteName = "NetworkingSiloRegistryGateFill.suite.\(UUID().uuidString)"
        standardName = "NetworkingSiloRegistryGateFill.standard.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        standard = UserDefaults(suiteName: standardName)!
        keychain = .inMemory(service: "NetworkingSiloRegistryGateFill.keychain.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: standard)
        launchPreferences = ProfileLaunchPreferences(defaults: defaults)
    }

    override func tearDown() {
        AuthService.shared.isLoggedIn = false
        suite.removePersistentDomain(forName: suiteName)
        standard.removePersistentDomain(forName: standardName)
        suite = nil
        standard = nil
        keychain = nil
        defaults = nil
        launchPreferences = nil
        super.tearDown()
    }

    private func makeRegistry(
        persistenceOverride: (([ServerEntry], String?) -> Bool)? = nil
    ) -> ServerRegistry {
        ServerRegistry(
            defaults: defaults,
            keychain: keychain,
            launchPreferences: launchPreferences,
            persistenceOverride: persistenceOverride
        )
    }

    func testRemoveUnknownServerFailsClosed() async {
        let registry = makeRegistry()
        let removed = await registry.remove(serverId: "missing-server")
        XCTAssertFalse(removed)
    }

    func testRemovePersistFailureRollsBackNonActiveEntry() async {
        let keep = ServerRegistry.serverId(for: "https://keep.example")
        let drop = ServerRegistry.serverId(for: "https://drop.example")
        var allowPersist = true
        let registry = makeRegistry { _, _ in allowPersist }
        registry.addOrUpdate(ServerEntry(
            id: keep, url: "https://keep.example", fetchedName: "Keep",
            profileId: "pk", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: drop, url: "https://drop.example", fetchedName: "Drop",
            profileId: "pd", lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        await registry.switchTo(serverId: keep)

        allowPersist = false
        let removed = await registry.remove(serverId: drop)
        XCTAssertFalse(removed)
        XCTAssertNotNil(registry.entry(with: drop))
        XCTAssertEqual(registry.activeServerId, keep)
    }

    func testRemoveActivePersistFailureRollsBack() async {
        let active = ServerRegistry.serverId(for: "https://active.example")
        let fallback = ServerRegistry.serverId(for: "https://fallback.example")
        var allowPersist = true
        let registry = makeRegistry { _, _ in allowPersist }
        registry.addOrUpdate(ServerEntry(
            id: active, url: "https://active.example", fetchedName: "Active",
            profileId: "pa", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: fallback, url: "https://fallback.example", fetchedName: "Fallback",
            profileId: "pf", lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        await registry.switchTo(serverId: active)

        allowPersist = false
        let removed = await registry.remove(serverId: active)
        XCTAssertFalse(removed)
        XCTAssertEqual(registry.activeServerId, active)
        XCTAssertNotNil(registry.entry(with: active))
    }

    func testGatedCommitSwitchRejectsStaleLeaseAndRefreshFeaturesRuns() async {
        let registry = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://gated.example")
        registry.addOrUpdate(ServerEntry(
            id: id, url: "https://gated.example", fetchedName: "Gated",
            profileId: nil, lastUsedAt: Date()
        ))

        // Fabricate an inactive lease by beginning and ending a transition.
        // beginIdentityTransition queues when a lease is already held, so never
        // nest a second acquisition against HTTPClient.shared in these tests.
        let lease = await HTTPClient.shared.beginIdentityTransition()
        if let lease {
            await HTTPClient.shared.endIdentityTransition(lease)
            let committed = await registry.commitSwitchTo(serverId: id, holding: lease)
            XCTAssertFalse(committed)
        }

        await registry.refreshFeaturesAfterGatedServerSwitch()
        await registry.switchTo(serverId: id)
        XCTAssertEqual(registry.activeServerId, id)
    }

    func testGatedCommitSwitchSucceedsWithLiveLease() async {
        let registry = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://live-lease.example")
        registry.addOrUpdate(ServerEntry(
            id: id, url: "https://live-lease.example", fetchedName: "Live",
            profileId: "p-live", lastUsedAt: Date()
        ))
        guard let lease = await HTTPClient.shared.beginIdentityTransition() else {
            XCTFail("expected identity transition lease")
            return
        }
        let committed = await registry.commitSwitchTo(serverId: id, holding: lease)
        // Always release before asserts so a failure cannot leave HTTPClient.shared
        // blocked for later suites (beginIdentityTransition queues, it does not fail).
        await HTTPClient.shared.endIdentityTransition(lease)
        XCTAssertTrue(committed)
        XCTAssertEqual(registry.activeServerId, id)
        XCTAssertEqual(defaults.string(forKey: "profileId"), "p-live")
    }

    func testUpdateFetchedNameAndProfileIdShim() {
        let registry = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://name.example")
        var entry = ServerEntry(
            id: id, url: "https://name.example", fetchedName: nil,
            profileId: nil, lastUsedAt: Date()
        )
        entry.profileId = "shim-profile"
        XCTAssertEqual(entry.profileId, "shim-profile")
        registry.addOrUpdate(entry)
        XCTAssertTrue(registry.updateFetchedName(for: id, fetchedName: "Named"))
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Named")
        // No equality short-circuit: repeating the same name still persists.
        XCTAssertTrue(registry.updateFetchedName(for: id, fetchedName: "Named"))
        // Nil / empty leave the existing display name in place.
        XCTAssertTrue(registry.updateFetchedName(for: id, fetchedName: nil))
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Named")
        XCTAssertTrue(registry.updateFetchedName(for: id, fetchedName: ""))
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Named")
        XCTAssertFalse(registry.updateFetchedName(for: "missing-server", fetchedName: "Nope"))
        registry.setProfileId("next-profile", for: id)
        XCTAssertEqual(registry.entry(with: id)?.profileId, "next-profile")
    }

    func testAddOrUpdatePreservesOrReplacesLegacyProfileAndFetchedName() {
        let registry = makeRegistry()
        let id = ServerRegistry.serverId(for: "https://merge.example")
        registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://merge.example",
            fetchedName: "Original",
            profileId: "legacy-a",
            lastUsedAt: Date(timeIntervalSince1970: 1)
        ))

        let preserved = registry.addOrUpdate(
            ServerEntry(
                id: id,
                url: "https://merge.example",
                fetchedName: nil,
                profileId: nil,
                lastUsedAt: Date(timeIntervalSince1970: 2)
            ),
            preservingProfile: true
        )
        XCTAssertEqual(preserved?.fetchedName, "Original")
        XCTAssertEqual(preserved?.profileId, "legacy-a")

        let replaced = registry.addOrUpdate(
            ServerEntry(
                id: id,
                url: "https://merge.example",
                fetchedName: "",
                profileId: nil,
                lastUsedAt: Date(timeIntervalSince1970: 3)
            ),
            preservingProfile: false
        )
        XCTAssertEqual(replaced?.fetchedName, "Original")
        XCTAssertNil(replaced?.profileId)
    }

    func testRemoveWithResolveFallbackProfileFlag() async {
        let registry = makeRegistry()
        let only = ServerRegistry.serverId(for: "https://solo-resolve.example")
        registry.addOrUpdate(ServerEntry(
            id: only, url: "https://solo-resolve.example", fetchedName: "Solo",
            profileId: "solo", lastUsedAt: Date()
        ))
        await registry.switchTo(serverId: only)
        AuthService.shared.isLoggedIn = true
        defer { AuthService.shared.isLoggedIn = false }
        // AuthService stub resolve returns false, but still executes the gated
        // remove path with the flag set while logged in.
        let removed = await registry.remove(serverId: only, resolveFallbackProfile: true)
        XCTAssertTrue(removed)
        XCTAssertTrue(registry.entries.isEmpty)
    }

    func testAddOrUpdateAndFetchedNamePersistFailuresRollBack() {
        var allowPersist = true
        let registry = makeRegistry { _, _ in allowPersist }
        let id = ServerRegistry.serverId(for: "https://persist-fail.example")

        allowPersist = false
        let added = registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://persist-fail.example",
            fetchedName: "Fail",
            profileId: "p",
            lastUsedAt: Date()
        ))
        XCTAssertNil(added)
        XCTAssertNil(registry.entry(with: id))

        allowPersist = true
        XCTAssertNotNil(registry.addOrUpdate(ServerEntry(
            id: id,
            url: "https://persist-fail.example",
            fetchedName: "Ok",
            profileId: "p",
            lastUsedAt: Date()
        )))
        allowPersist = false
        XCTAssertFalse(registry.updateFetchedName(for: id, fetchedName: "Nope"))
        XCTAssertEqual(registry.entry(with: id)?.fetchedName, "Ok")
    }

    func testSwitchToUnknownPersistFailureAndLegacyPinDiscard() async {
        let registry = makeRegistry()
        let missingSwitched = await registry.switchTo(serverId: "missing")
        XCTAssertFalse(missingSwitched)

        let keep = ServerRegistry.serverId(for: "https://keep-pin.example")
        let other = ServerRegistry.serverId(for: "https://other-pin.example")
        registry.addOrUpdate(ServerEntry(
            id: keep, url: "https://keep-pin.example", fetchedName: "Keep",
            profileId: "pk", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: other, url: "https://other-pin.example", fetchedName: "Other",
            profileId: "po", lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        // Incomplete legacy migration pin: switching away discards leftover
        // fixed-name keychain accounts.
        defaults.set(false, forKey: "continuumServerRegistry.migrated.v1")
        defaults.set("https://keep-pin.example", forKey: "continuumServerRegistry.legacySourceUrl.v1")
        AuthService.shared.isLoggedIn = true
        defer { AuthService.shared.isLoggedIn = false }
        let switched = await registry.switchTo(serverId: other, resolveDestinationProfile: true)
        XCTAssertTrue(switched)
        XCTAssertEqual(registry.activeServerId, other)
    }

    func testSwitchToPersistFailureRollsBackDestination() async {
        var allowPersist = true
        let registry = makeRegistry { _, _ in allowPersist }
        let a = ServerRegistry.serverId(for: "https://switch-a.example")
        let b = ServerRegistry.serverId(for: "https://switch-b.example")
        registry.addOrUpdate(ServerEntry(
            id: a, url: "https://switch-a.example", fetchedName: "A",
            profileId: "pa", lastUsedAt: Date(timeIntervalSince1970: 2)
        ))
        registry.addOrUpdate(ServerEntry(
            id: b, url: "https://switch-b.example", fetchedName: "B",
            profileId: "pb", lastUsedAt: Date(timeIntervalSince1970: 1)
        ))
        let switchedA = await registry.switchTo(serverId: a)
        XCTAssertTrue(switchedA)
        allowPersist = false
        let switchedB = await registry.switchTo(serverId: b)
        XCTAssertFalse(switchedB)
        XCTAssertEqual(registry.activeServerId, a)
    }
}

final class NetworkingSiloTokenStoreGateFillTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!
    private var keychain: SharedKeychain!
    private var defaults: SharedDefaults!
    private var serverID: String!

    override func setUp() {
        super.setUp()
        suiteName = "NetworkingSiloTokenStoreGateFill.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        keychain = .inMemory(service: "NetworkingSiloTokenStoreGateFill.\(UUID().uuidString)")
        defaults = SharedDefaults(suite: suite, standard: suite)
        serverID = ServerRegistry.serverId(for: "https://silo-gate.example")
    }

    override func tearDown() {
        for key in [
            TokenStore.accessTokenKey(for: serverID),
            TokenStore.refreshTokenKey(for: serverID),
            TokenStore.profileTokenKey(for: serverID),
            TokenStore.accountEpochKey(for: serverID),
            SharedStorage.mirroredAccessTokenAccount,
            SharedStorage.mirroredProfileTokenAccount,
        ] {
            keychain.delete(key)
        }
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        keychain = nil
        defaults = nil
        super.tearDown()
    }

    private func makeStore() -> TokenStore {
        TokenStore(keychain: keychain, defaults: defaults)
    }

    func testAccountEpochRotatesAndRejectsStaleActivation() async throws {
        let store = makeStore()
        await store.switchActiveServer(serverId: serverID)
        await store.setServerUrl("https://silo-gate.example")
        await store.saveTokens(accessToken: "access-a", refreshToken: "refresh-a")

        let firstEpochValue = await store.getOrCreateAccountEpoch()
        let firstEpoch = try XCTUnwrap(firstEpochValue)
        let firstAccountValue = await store.refreshAccountIdentity()
        let firstAccount = try XCTUnwrap(firstAccountValue)
        await store.saveTokens(accessToken: "access-b", refreshToken: "refresh-b")
        let secondEpochValue = await store.getOrCreateAccountEpoch()
        let secondEpoch = try XCTUnwrap(secondEpochValue)
        let staleActivation = await store.activateProfile(
            profileID: "profile-a",
            profileToken: nil,
            expectedAccount: firstAccount
        )

        XCTAssertNotEqual(firstEpoch, secondEpoch)
        XCTAssertFalse(staleActivation)
        let hasToken = await store.hasStoredProfileToken(for: serverID)
        XCTAssertFalse(hasToken)
        let emptyEpoch = await store.getOrCreateAccountEpoch(for: "")
        XCTAssertNil(emptyEpoch)
        let emptyHasToken = await store.hasStoredProfileToken(for: "")
        XCTAssertFalse(emptyHasToken)
    }

    func testProfileCommitIsAtomicAndLateDeactivationCannotClearReplacement() async throws {
        let store = makeStore()
        await store.switchActiveServer(serverId: serverID)
        await store.setServerUrl("https://silo-gate.example")
        await store.saveTokens(accessToken: "access", refreshToken: "refresh")
        let accountValue = await store.refreshAccountIdentity()
        let account = try XCTUnwrap(accountValue)

        let activatedA = await store.activateProfile(
            profileID: "profile-a",
            profileToken: "proof-a",
            expectedAccount: account
        )
        let profileA = await store.getProfileId()
        let proofA = await store.getProfileToken()
        let hasProof = await store.hasStoredProfileToken(for: serverID)
        XCTAssertTrue(activatedA)
        XCTAssertEqual(profileA, "profile-a")
        XCTAssertEqual(proofA, "proof-a")
        XCTAssertTrue(hasProof)

        let activatedB = await store.activateProfile(
            profileID: "profile-b",
            profileToken: nil,
            expectedAccount: account
        )
        let lateDeactivation = await store.deactivateProfile(
            expectedAccount: account,
            expectedProfileID: "profile-a"
        )
        let profileB = await store.getProfileId()
        let proofB = await store.getProfileToken()
        XCTAssertTrue(activatedB)
        XCTAssertFalse(lateDeactivation)
        XCTAssertEqual(profileB, "profile-b")
        XCTAssertNil(proofB)

        let cleared = await store.deactivateProfile(expectedAccount: account)
        let profileAfterClear = await store.getProfileId()
        XCTAssertTrue(cleared)
        XCTAssertNil(profileAfterClear)
    }

    func testTemporaryRemoteIdentityRefusesPersistentProfileMutation() async throws {
        let store = makeStore()
        await store.switchActiveServer(serverId: serverID)
        await store.setServerUrl("https://silo-gate.example")
        await store.saveTokens(accessToken: "access", refreshToken: "refresh")
        let persistentAccountValue = await store.refreshAccountIdentity()
        let persistentAccount = try XCTUnwrap(persistentAccountValue)
        await store.beginTemporaryScope(TemporaryAuthScope(
            serverId: "remote-server",
            serverURL: "https://remote.example",
            accessToken: "remote-access",
            refreshToken: "remote-refresh",
            profileId: "remote-profile",
            profileToken: "remote-proof",
            controllerDeviceId: "controller",
            expiresAt: Date().addingTimeInterval(60)
        ))

        let activation = await store.activateProfile(
            profileID: "persistent-profile",
            profileToken: nil,
            expectedAccount: persistentAccount
        )
        let deactivation = await store.deactivateProfile(expectedAccount: persistentAccount)
        let profileID = await store.getProfileId()
        let epoch = await store.getOrCreateAccountEpoch()
        XCTAssertFalse(activation)
        XCTAssertFalse(deactivation)
        XCTAssertEqual(profileID, "remote-profile")
        XCTAssertNil(epoch)
    }

    func testAccountEpochKeyDerivationHelper() {
        XCTAssertEqual(
            TokenStore.accountEpochKey(for: "abc"),
            SharedStorage.accountEpochAccount(for: "abc")
        )
        XCTAssertEqual(TokenStore.accountCredentialAudience, .userIndependent)
        XCTAssertEqual(TokenStore.profileCredentialAudience, .currentUser)
    }

    func testRetargetAndOrdinaryRequestAuthCapture() async throws {
        let store = makeStore()
        await store.switchActiveServer(serverId: serverID)
        await store.setServerUrl("https://silo-gate.example")
        await store.saveTokens(accessToken: "access", refreshToken: "refresh")
        await store.setProfileId("profile-1")
        await store.setProfileToken("proof-1")

        await store.retargetActiveServer(serverId: serverID)
        let ordinary = await store.captureOrdinaryRequestAuth()
        XCTAssertEqual(ordinary?.accessToken, "access")
        XCTAssertEqual(ordinary?.profileId, "profile-1")

        let accountValue = await store.refreshAccountIdentity()
        let account = try XCTUnwrap(accountValue)
        let identity = HTTPRequestIdentity(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            profileId: "profile-1",
            clientFamily: "ios"
        )
        let captured = try await store.captureRequestAuth(expected: identity)
        XCTAssertEqual(captured.accessToken, "access")
        XCTAssertEqual(captured.account.serverId, account.serverId)

        do {
            _ = try await store.captureRequestAuth(
                expected: HTTPRequestIdentity(
                    serverId: serverID,
                    serverURL: "https://silo-gate.example",
                    profileId: "other-profile",
                    clientFamily: "ios"
                )
            )
            XCTFail("expected identity mismatch")
        } catch HTTPError.requestIdentityChanged {
            // expected
        }
    }

    func testClearTokensCoversTemporaryAndEmptyActiveServerBranches() async {
        let store = makeStore()
        await store.beginTemporaryScope(TemporaryAuthScope(
            serverId: "remote-server",
            serverURL: "https://remote.example",
            accessToken: "remote-access",
            refreshToken: "remote-refresh",
            profileId: "remote-profile",
            profileToken: "remote-proof",
            controllerDeviceId: "controller",
            expiresAt: Date().addingTimeInterval(60)
        ))
        await store.clearTokens()
        let temporaryAfterClear = await store.getTemporaryScope()
        XCTAssertNil(temporaryAfterClear)

        // No active server: still clears in-memory state and records the branch.
        await store.clearTokens()
        let access = await store.getAccessToken()
        XCTAssertNil(access)
    }

    func testPersistentRefreshRotationAndRejectedRefreshClear() async throws {
        let store = makeStore()
        await store.switchActiveServer(serverId: serverID)
        await store.setServerUrl("https://silo-gate.example")
        await store.setProfileId("profile-1")
        await store.saveTokens(accessToken: "access", refreshToken: "refresh")

        let identity = HTTPRequestIdentity(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            profileId: "profile-1",
            clientFamily: "ios"
        )

        let rotated = await store.saveRefreshedTokens(
            "access-2",
            "refresh-2",
            replacing: "refresh",
            expected: identity,
            credentialOwner: .persistentServer(serverId: serverID)
        )
        let accessAfterRotate = await store.getAccessToken()
        let refreshAfterRotate = await store.getRefreshToken()
        XCTAssertTrue(rotated)
        XCTAssertEqual(accessAfterRotate, "access-2")
        XCTAssertEqual(refreshAfterRotate, "refresh-2")

        let liveAccountValue = await store.refreshAccountIdentity()
        let liveAccount = try XCTUnwrap(liveAccountValue)
        let liveCapturedValue = await store.captureRefreshCredential(expected: liveAccount)
        let liveCaptured = try XCTUnwrap(liveCapturedValue)
        XCTAssertEqual(liveCaptured.refreshToken, "refresh-2")

        let cleared = await store.clearTokensAfterRejectedRefresh(
            replacing: "refresh-2",
            expected: identity,
            credentialOwner: .persistentServer(serverId: serverID)
        )
        let refreshAfterClear = await store.getRefreshToken()
        XCTAssertTrue(cleared)
        XCTAssertNil(refreshAfterClear)

        // Stale capture from before the clear must not wipe a later session.
        let disposition = await store.invalidateRejectedRefresh(liveCaptured)
        XCTAssertNil(disposition)
    }

    func testTemporaryRefreshRotationAndClearTokensShapes() async throws {
        let store = makeStore()
        await store.switchActiveServer(serverId: serverID)
        await store.setServerUrl("https://silo-gate.example")
        await store.saveTokens(accessToken: "access", refreshToken: "refresh")

        let temporary = TemporaryAuthScope(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            accessToken: "temp-access",
            refreshToken: "temp-refresh",
            profileId: "temp-profile",
            profileToken: "temp-proof",
            controllerDeviceId: "controller",
            expiresAt: Date().addingTimeInterval(60)
        )
        await store.beginTemporaryScope(temporary)
        let accountValue = await store.refreshAccountIdentity()
        let account = try XCTUnwrap(accountValue)
        let captured = CapturedRefreshCredential(
            account: account,
            refreshToken: "temp-refresh",
            owner: .temporary
        )
        let rotated = await store.saveRefreshedTokens(
            "temp-access-2",
            "temp-refresh-2",
            replacing: captured
        )
        let scopeAfterRotate = await store.getTemporaryScope()
        XCTAssertTrue(rotated)
        XCTAssertEqual(scopeAfterRotate?.accessToken, "temp-access-2")
        XCTAssertEqual(scopeAfterRotate?.refreshToken, "temp-refresh-2")

        let rotatedCaptured = CapturedRefreshCredential(
            account: account,
            refreshToken: "temp-refresh-2",
            owner: .temporary
        )
        let disposition = await store.invalidateRejectedRefresh(rotatedCaptured)
        XCTAssertEqual(disposition, .temporarySessionExpired)
    }

    func testRestoreTemporaryScopeAndRejectedRefreshShapeGuards() async throws {
        let store = makeStore()
        await store.switchActiveServer(serverId: serverID)
        await store.setServerUrl("https://silo-gate.example")
        await store.saveTokens(accessToken: "access", refreshToken: "refresh")

        let first = TemporaryAuthScope(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            accessToken: "t1",
            refreshToken: "r1",
            profileId: "p1",
            profileToken: "k1",
            controllerDeviceId: "c1",
            expiresAt: Date().addingTimeInterval(60)
        )
        _ = await store.beginTemporaryScope(first)
        let second = TemporaryAuthScope(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            accessToken: "t2",
            refreshToken: "r2",
            profileId: "p2",
            profileToken: "k2",
            controllerDeviceId: "c2",
            expiresAt: Date().addingTimeInterval(60)
        )
        // beginTemporaryScope returns the *previous* overlay; capture it when
        // installing `second` so restore can put `first` back.
        let snapshot = await store.beginTemporaryScope(second)
        let restored = await store.restoreTemporaryScope(
            snapshot,
            replacingGenerationID: second.credentialGenerationID
        )
        let scope = await store.getTemporaryScope()
        XCTAssertTrue(restored)
        XCTAssertEqual(scope?.accessToken, "t1")

        let stale = await store.restoreTemporaryScope(
            snapshot,
            replacingGenerationID: UUID()
        )
        XCTAssertFalse(stale)

        let identity = HTTPRequestIdentity(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            profileId: "p1",
            clientFamily: "ios"
        )
        let skippedNil = await store.clearTokensAfterRejectedRefresh(
            replacing: nil,
            expected: identity,
            credentialOwner: .persistentServer(serverId: serverID)
        )
        let skippedTemporaryOwner = await store.clearTokensAfterRejectedRefresh(
            replacing: "r1",
            expected: identity,
            credentialOwner: .temporary
        )
        XCTAssertFalse(skippedNil)
        XCTAssertFalse(skippedTemporaryOwner)

        // Cover the restore path that re-applies a prior rejection bit.
        let rejected = TemporaryAuthScope(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            accessToken: "t3",
            refreshToken: "r3",
            profileId: "p3",
            profileToken: "k3",
            controllerDeviceId: "c3",
            expiresAt: Date().addingTimeInterval(60)
        )
        _ = await store.beginTemporaryScope(rejected)
        let rejectedAccountValue = await store.refreshAccountIdentity()
        let rejectedAccount = try XCTUnwrap(rejectedAccountValue)
        _ = await store.invalidateRejectedRefresh(CapturedRefreshCredential(
            account: rejectedAccount,
            refreshToken: "r3",
            owner: .temporary
        ))
        let replacement = TemporaryAuthScope(
            serverId: serverID,
            serverURL: "https://silo-gate.example",
            accessToken: "t4",
            refreshToken: "r4",
            profileId: "p4",
            profileToken: "k4",
            controllerDeviceId: "c4",
            expiresAt: Date().addingTimeInterval(60)
        )
        let rejectedSnapshot = await store.beginTemporaryScope(replacement)
        let restoredRejected = await store.restoreTemporaryScope(
            rejectedSnapshot,
            replacingGenerationID: replacement.credentialGenerationID
        )
        let restoredAccess = await store.getTemporaryScope()?.accessToken
        XCTAssertTrue(restoredRejected)
        XCTAssertEqual(restoredAccess, "t3")
    }
}
