//
//  NetworkingUpstreamGateFillTests.swift
//  PrairieNetworkingTests
//
//  Closes coverage gaps the 2026-10-12 upstream merge introduced: new
//  Networking models and helpers whose upstream tests drive app view models
//  (LoginViewModel, AppRouter, PlayerViewModel) and so run only in the app
//  test bundles, not the thin Networking host.
//

import XCTest
import Foundation
@testable import Prairie

@MainActor
final class NetworkingUpstreamGateFillTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func problem(_ status: Int) throws -> APIv2Problem {
        try decode(APIv2Problem.self, #"{"type":"about:blank","title":"t","status":\#(status),"detail":"d"}"#)
    }

    // MARK: - External sign-in models

    private func provider(
        _ id: String,
        mode: String,
        name: String = "Provider",
        iconUrl: String? = nil,
        nativeStartPath: String? = nil,
        networkSignInPath: String? = nil
    ) -> APIv2AuthProvider {
        APIv2AuthProvider(id: id, displayName: name, mode: mode, default: false, iconUrl: iconUrl,
                          nativeStartPath: nativeStartPath, networkSignInPath: networkSignInPath)
    }

    func testAuthProviderModesAndNetworkIdentityName() {
        XCTAssertTrue(provider("a", mode: "oauth").isOAuth)
        XCTAssertTrue(provider("b", mode: "credentials").isCredentials)
        XCTAssertTrue(provider("c", mode: "network").isNetwork)
        XCTAssertFalse(provider("d", mode: "saml").isOAuth)

        XCTAssertEqual(APIv2AuthProviderNetworkIdentity(displayName: " Ann ", username: "ann").name, "Ann")
        XCTAssertEqual(APIv2AuthProviderNetworkIdentity(displayName: "  ", username: " bob ").name, "bob")
        XCTAssertNil(APIv2AuthProviderNetworkIdentity().name)
    }

    func testOAuthAndExternalSignInCapabilities() {
        let full = APIv2OAuthCapabilities(state: "available", native: true, linking: true, selectAccount: true)
        XCTAssertTrue(full.supportsNative)
        XCTAssertTrue(full.supportsLinking)
        XCTAssertTrue(full.supportsSelectAccount)
        let old = APIv2OAuthCapabilities(state: "available")
        XCTAssertFalse(old.supportsNative)
        XCTAssertFalse(old.supportsLinking)
        XCTAssertFalse(old.supportsSelectAccount)
        XCTAssertFalse(APIv2OAuthCapabilities(state: "disabled", native: true, selectAccount: true).supportsSelectAccount)

        let ext = APIv2ExternalSignInCapabilities(state: "available", identities: true, credentialsLinking: true,
                                                  networkSignIn: true, networkLinkKeepsPassword: true)
        XCTAssertTrue(ext.supportsIdentities)
        XCTAssertTrue(ext.supportsCredentialsLinking)
        XCTAssertTrue(ext.supportsNetworkSignIn)
        XCTAssertTrue(ext.keepsPasswordOnNetworkLink)
        let bare = APIv2ExternalSignInCapabilities(state: "unavailable")
        XCTAssertFalse(bare.supportsIdentities)
        XCTAssertFalse(bare.supportsCredentialsLinking)
        XCTAssertFalse(bare.supportsNetworkSignIn)
        XCTAssertFalse(bare.keepsPasswordOnNetworkLink)
    }

    func testAccountIdentityLabelFallsBackThroughUsernameEmailAndDisplayName() {
        func identity(_ username: String, _ email: String, _ displayName: String) -> APIv2AccountIdentity {
            APIv2AccountIdentity(id: "1", installationId: "2", providerId: nil, providerName: "P",
                                 username: username, email: email, displayName: displayName, linkedAt: Date())
        }
        XCTAssertEqual(identity("ann", "a@x", "Ann").accountLabel, "ann")
        XCTAssertEqual(identity(" ", "a@x", "Ann").accountLabel, "a@x")
        XCTAssertEqual(identity("", "", " Ann ").accountLabel, "Ann")
        XCTAssertEqual(identity("", "", "").accountLabel, "")
        XCTAssertNil(identity("a", "", "").lastSignInAt)
        XCTAssertNil(APIv2AccountIdentities(items: []).canUnlink)
    }

    func testSignInOptionsFromDiscovery() {
        XCTAssertEqual(SignInOptions(providers: nil, oauth: nil), .passwordOnly)
        XCTAssertTrue(SignInOptions.passwordOnly.showsPasswordForm)
        XCTAssertFalse(SignInOptions.passwordOnly.offersNoSignIn)

        let browser = provider("7", mode: "oauth", name: "Keycloak",
                               nativeStartPath: "/prairie/api/v2/auth/oauth/7/native/start?x=1")
        let noStart = provider("8", mode: "oauth")
        let network = provider("9", mode: "network", networkSignInPath: "/api/v2/auth/network/3/sign-in")
        let badNetwork = provider("10", mode: "network", networkSignInPath: "https://evil.example/sign-in")
        let password = provider("11", mode: "credentials")
        let providers = APIv2AuthProviders(items: [browser, noStart, network, badNetwork, password], passwordLogin: false)
        let oauth = APIv2OAuthCapabilities(state: "available", native: true, selectAccount: true)

        let options = SignInOptions(providers: providers, oauth: oauth)
        XCTAssertEqual(options.browserProviders, [browser])
        XCTAssertFalse(options.acceptsPasswords)
        XCTAssertFalse(options.showsPasswordForm)
        XCTAssertTrue(options.supportsSelectAccount)
        XCTAssertEqual(options.oauthProviders, [browser, noStart])
        XCTAssertEqual(options.networkProviders, [network])
        XCTAssertFalse(options.offersNoSignIn)

        let noNative = SignInOptions(providers: APIv2AuthProviders(items: [browser]), oauth: nil)
        XCTAssertTrue(noNative.browserProviders.isEmpty)
        XCTAssertTrue(noNative.acceptsPasswords)
        XCTAssertFalse(noNative.supportsSelectAccount)

        let nothing = SignInOptions(providers: APIv2AuthProviders(items: [noStart], passwordLogin: false), oauth: oauth)
        XCTAssertTrue(nothing.offersNoSignIn)

        let explicit = SignInOptions(browserProviders: [browser], acceptsPasswords: true, supportsSelectAccount: false)
        XCTAssertEqual(explicit.oauthProviders, [browser])
        XCTAssertTrue(explicit.networkProviders.isEmpty)

        XCTAssertEqual(SignInDiscovery.loaded(options).options, options)
        XCTAssertNil(SignInDiscovery.failed.options)
        XCTAssertNil(SignInDiscovery.loading.options)
    }

    func testSignInOptionsNativeStartTitlesNamesAndIcons() {
        let start = SignInOptions.nativeStart(of: provider("7", mode: "oauth",
            nativeStartPath: "/base/api/v2/auth/oauth/7/native/start?prompt=login"))
        XCTAssertEqual(start?.apiPath, "/api/v2/auth/oauth/7/native/start")
        XCTAssertEqual(start?.queryItems, [URLQueryItem(name: "prompt", value: "login")])
        XCTAssertNil(SignInOptions.nativeStart(of: provider("8", mode: "oauth")))

        XCTAssertEqual(SignInOptions.buttonTitle(for: provider("a", mode: "oauth", name: " ")),
                       "Sign in with single sign-on")
        XCTAssertEqual(SignInOptions.buttonTitle(for: provider("a", mode: "oauth", name: "Sign in with authentik")),
                       "Sign in with authentik")
        XCTAssertEqual(SignInOptions.buttonTitle(for: provider("a", mode: "oauth", name: "Keycloak")),
                       "Sign in with Keycloak")

        XCTAssertEqual(SignInOptions.providerName(for: provider("a", mode: "oauth", name: "Sign in with Keycloak")),
                       "Keycloak")
        XCTAssertEqual(SignInOptions.providerName(for: provider("a", mode: "oauth", name: "")), "single sign-on")
        XCTAssertEqual(SignInOptions.providerName(for: provider("a", mode: "oauth", name: "Okta")), "Okta")

        let relative = SignInOptions.iconURL(for: provider("a", mode: "oauth", iconUrl: "/icons/a.png"),
                                             serverURL: "https://media.example")
        XCTAssertEqual(relative?.host, "media.example")
        XCTAssertEqual(relative?.path, "/icons/a.png")
        XCTAssertEqual(SignInOptions.iconURL(for: provider("a", mode: "oauth", iconUrl: "https://cdn.example/i.png"),
                                             serverURL: "https://media.example"),
                       URL(string: "https://cdn.example/i.png"))
        XCTAssertNil(SignInOptions.iconURL(for: provider("a", mode: "oauth", iconUrl: "javascript:alert(1)"),
                                           serverURL: "https://media.example"))
        XCTAssertNil(SignInOptions.iconURL(for: provider("a", mode: "oauth", iconUrl: "  "),
                                           serverURL: "https://media.example"))
        XCTAssertNil(SignInOptions.iconURL(for: provider("a", mode: "oauth"), serverURL: "https://media.example"))
    }

    // MARK: - ServerAuthPath

    func testServerAuthPathKeepsOnlyTheRelativeAPIPath() {
        let start = ServerAuthPath.relative("/base/api/v2/auth/oauth/abc/native/start?a=b",
                                            suffix: ServerAuthPath.nativeStart, allowsQuery: true)
        XCTAssertEqual(start?.apiPath, "/api/v2/auth/oauth/abc/native/start")
        XCTAssertEqual(start?.queryItems, [URLQueryItem(name: "a", value: "b")])
        XCTAssertNil(ServerAuthPath.relative("/api/v2/auth/oauth/abc/native/start?a=b",
                                             suffix: ServerAuthPath.nativeStart, allowsQuery: false))
        XCTAssertNil(ServerAuthPath.relative("//evil.example/api/v2/auth/oauth/abc/native/start",
                                             suffix: ServerAuthPath.nativeStart, allowsQuery: true))
        XCTAssertNil(ServerAuthPath.relative("https://evil.example/api/v2/auth/oauth/abc/native/start",
                                             suffix: ServerAuthPath.nativeStart, allowsQuery: true))
        XCTAssertNil(ServerAuthPath.relative("/other", suffix: ServerAuthPath.nativeStart, allowsQuery: true))
        XCTAssertNil(ServerAuthPath.relative(nil, suffix: ServerAuthPath.nativeStart, allowsQuery: true))

        XCTAssertTrue(ServerAuthPath.isNetworkSignIn("/prefix/api/v2/auth/network/12/sign-in"))
        XCTAssertFalse(ServerAuthPath.isNetworkSignIn("/api/v2/auth/network/0/sign-in"))
        XCTAssertFalse(ServerAuthPath.isNetworkSignIn("/api/v2/items"))
    }

    // MARK: - Server branding

    func testServerBrandingResolvesSameOriginAssetsOnly() {
        let document = ServerBrandingDocument(serverName: " Home ", loginSubtitle: "", accentColor: "#123456",
                                              wordmarkUrl: "/branding/w.png", markUrl: "https://evil.example/m.png")
        let branding = ServerBranding(document: document, baseURL: "https://media.example/prairie")
        XCTAssertEqual(branding.serverName, "Home")
        XCTAssertNil(branding.loginSubtitle)
        XCTAssertEqual(branding.accentColor, "#123456")
        XCTAssertEqual(branding.wordmarkURL, URL(string: "https://media.example/prairie/branding/w.png"))
        XCTAssertNil(branding.markURL)

        XCTAssertEqual(ServerBranding.resolve("logo.png", base: "https://media.example:443/"),
                       URL(string: "https://media.example:443/logo.png"))
        XCTAssertNil(ServerBranding.resolve(nil, base: "https://media.example"))
        XCTAssertNil(ServerBranding.resolve("  ", base: "https://media.example"))

        XCTAssertEqual(ServerBranding.hostLabel("https://media.example:8443/x"), "media.example:8443")
        XCTAssertEqual(ServerBranding.hostLabel("https://media.example"), "media.example")
        XCTAssertEqual(ServerBranding.hostLabel("not a url"), "not a url")

        XCTAssertEqual(ServerBranding.displayName(branding, serverURL: "https://media.example"), "Home")
        XCTAssertFalse(ServerBranding.displayName(nil, serverURL: "https://media.example").isEmpty)
    }

    func testServerBrandingCacheStoresAndForgetsPerServer() throws {
        let serverURL = "https://gatefill-\(UUID().uuidString.lowercased()).example"
        let document = ServerBrandingDocument(serverName: "Cached", loginSubtitle: nil, accentColor: nil,
                                              wordmarkUrl: nil, markUrl: "/m.png")
        let branding = ServerBranding(document: document, baseURL: serverURL)
        defer { ServerBrandingCache.remove(for: serverURL) }

        XCTAssertNil(ServerBrandingCache.branding(for: serverURL))
        ServerBrandingCache.store(branding, for: serverURL)
        XCTAssertEqual(ServerBrandingCache.branding(for: serverURL), branding)
        ServerBrandingCache.remove(for: serverURL)
        XCTAssertNil(ServerBrandingCache.branding(for: serverURL))

        let roundTrip = try JSONDecoder().decode(ServerBranding.self, from: JSONEncoder().encode(branding))
        XCTAssertEqual(roundTrip, branding)
    }

    // MARK: - Device login

    func testDeviceUserCodeFormatting() {
        XCTAssertEqual(DeviceUserCode.normalized("ab-cd 12"), "ABCD12")
        XCTAssertEqual(DeviceUserCode.display("4821-7730"), "4821 7730")
        XCTAssertEqual(DeviceUserCode.display(" abc "), "abc")
        XCTAssertEqual(DeviceUserCode.spokenCharacters("ab-1"), "A B 1")
        XCTAssertEqual(DeviceUserCode.entryText("4821-77301x"), "4821 7730")
        XCTAssertEqual(DeviceUserCode.entryText("ab"), "AB")
        XCTAssertTrue(DeviceUserCode.isComplete("abcd-efgh"))
        XCTAssertFalse(DeviceUserCode.isComplete("4821"))
        XCTAssertFalse(DeviceUserCode.isComplete("ÄBCD-EFGH"))
    }

    func testDeviceLoginModelDefaults() {
        let start = DeviceLoginStartResponse(deviceCode: "d", userCode: "u", matchCode: "m", verificationUri: "v",
                                             verificationUriComplete: "vc", expiresAt: Date(), expiresIn: 600,
                                             interval: 5, deviceName: "TV", devicePlatform: "tvos")
        XCTAssertNil(start.clientPurpose)
        XCTAssertNil(start.temporary)

        let lookup = DeviceLookupResponse(matchCode: "12", deviceName: "TV", devicePlatform: "tvos", status: "pending")
        XCTAssertNil(lookup.clientPurpose)
        XCTAssertNil(lookup.temporary)
        XCTAssertNil(lookup.userCode)
        XCTAssertNil(lookup.ipAddressHint)
        XCTAssertNil(lookup.expiresAt)
        XCTAssertNil(lookup.requestedAt)
        XCTAssertNil(lookup.serverId)
        XCTAssertNil(lookup.serverName)
        XCTAssertEqual(DeviceLoginStatus(raw: "approved"), .approved)
        XCTAssertEqual(DeviceLoginStatus(raw: "something-new"), .unknown)
    }

    func testDeviceLoginPollerClassifiesErrors() throws {
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.problem(try problem(404))), .removed)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.httpStatus(404)), .removed)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.incompleteAuthResponse), .terminal)
        XCTAssertEqual(DeviceLoginPoller.classify(HTTPError.requestIdentityChanged), .terminal)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.serverUpdateRequired), .terminal)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.problem(try problem(503))), .transient)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.problem(try problem(422))), .terminal)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.httpStatus(429)), .transient)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.httpStatus(408)), .transient)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.httpStatus(400)), .terminal)
        XCTAssertEqual(DeviceLoginPoller.classify(APIv2Error.httpStatus(302)), .transient)
        XCTAssertEqual(DeviceLoginPoller.classify(URLError(.notConnectedToInternet)), .transient)
    }

    private func devicePoll(_ status: String, pollAfter: Int) -> APIv2DevicePoll {
        APIv2DevicePoll(status: status, pollAfter: pollAfter, tokens: nil, profileId: "", profileToken: "",
                        temporary: false, sessionExpiresAt: nil)
    }

    /// Answers polls from a script, one entry per call.
    private final class PollScript {
        var answers: [Result<APIv2DevicePoll, any Error>]
        var sleeps: [Int] = []
        init(_ answers: [Result<APIv2DevicePoll, any Error>]) { self.answers = answers }
        func next() throws -> APIv2DevicePoll { try answers.removeFirst().get() }
    }

    private func awaitApproval(_ script: PollScript, interval: Int = 2, expiresIn: Int = 600,
                      now: @escaping () -> Date = { Date(timeIntervalSince1970: 0) }) async throws -> APIv2DevicePoll {
        try await DeviceLoginPoller.waitForApproval(
            interval: interval, expiresIn: expiresIn,
            poll: { try script.next() },
            sleep: { script.sleeps.append($0) },
            now: now
        )
    }

    func testDeviceLoginPollerRetriesTransientFailuresUntilApproved() async throws {
        let script = PollScript([
            .failure(URLError(.notConnectedToInternet)),
            .success(devicePoll("pending", pollAfter: 3)),
            .success(devicePoll("approved", pollAfter: 0)),
        ])
        let answer = try await awaitApproval(script)
        XCTAssertEqual(answer.status, "approved")
        XCTAssertEqual(script.sleeps, [2, 3])
    }

    func testDeviceLoginPollerEndsOnEveryTerminalAnswer() async throws {
        let endings: [(String, DeviceLoginPoller.Failure)] = [
            ("denied", .denied), ("expired", .expired), ("consumed", .consumed), ("canceled", .canceled),
        ]
        for (status, failure) in endings {
            do {
                _ = try await awaitApproval(PollScript([.success(devicePoll(status, pollAfter: 1))]))
                XCTFail("\(status) should end the wait")
            } catch let error as DeviceLoginPoller.Failure {
                XCTAssertEqual(error, failure)
            }
        }

        do {
            _ = try await awaitApproval(PollScript([.success(devicePoll("mystery", pollAfter: 1))]))
            XCTFail("an unknown status should end the wait")
        } catch APIv2Error.incompleteAuthResponse {
        }

        do {
            _ = try await awaitApproval(PollScript([.failure(APIv2Error.problem(try problem(404)))]))
            XCTFail("a removed request should end the wait")
        } catch let error as DeviceLoginPoller.Failure {
            XCTAssertEqual(error, .removed)
        }

        do {
            _ = try await awaitApproval(PollScript([.failure(APIv2Error.httpStatus(400))]))
            XCTFail("a client error should end the wait")
        } catch APIv2Error.httpStatus(let status) {
            XCTAssertEqual(status, 400)
        }
    }

    func testDeviceLoginPollerExpiresWhenTheCodeRunsOut() async throws {
        var clock = 0.0
        let script = PollScript([.success(devicePoll("pending", pollAfter: 0))])
        do {
            _ = try await awaitApproval(script, interval: 0, expiresIn: 15) {
                defer { clock += 10 }
                return Date(timeIntervalSince1970: clock)
            }
            XCTFail("the wait should expire")
        } catch let error as DeviceLoginPoller.Failure {
            XCTAssertEqual(error, .expired)
        }
        XCTAssertEqual(script.sleeps, [1])
    }

    // MARK: - Bonjour self-heal

    @MainActor
    private final class RestartCounter {
        var count = 0
    }

    func testBonjourSelfHealRestartsOnceForTheCurrentGeneration() async {
        let heal = BonjourSelfHeal(delay: .milliseconds(5))
        let counter = RestartCounter()
        XCTAssertEqual(BonjourSelfHeal.defaultDelay, .seconds(2))
        XCTAssertFalse(heal.isActive)
        heal.scheduleRestart { counter.count += 1 }
        XCTAssertNil(heal.pendingRestart, "an inactive owner never restarts")

        let generation = heal.activate()
        XCTAssertTrue(heal.isCurrent(generation))
        XCTAssertFalse(heal.isCurrent(generation - 1))
        heal.scheduleRestart { counter.count += 1 }
        heal.scheduleRestart { counter.count += 100 } // coalesced
        _ = await heal.pendingRestart?.value
        XCTAssertEqual(counter.count, 1)
        XCTAssertNil(heal.pendingRestart)
    }

    func testBonjourSelfHealDropsRestartsAfterStopOrNewerStart() async {
        let heal = BonjourSelfHeal(delay: .milliseconds(5))
        let counter = RestartCounter()

        let first = heal.activate()
        heal.scheduleRestart { counter.count += 1 }
        let superseded = heal.pendingRestart
        let second = heal.activate()
        _ = await superseded?.value
        XCTAssertFalse(heal.isCurrent(first))
        XCTAssertTrue(heal.isCurrent(second))

        heal.scheduleRestart { counter.count += 1 }
        let stopped = heal.pendingRestart
        heal.deactivate()
        _ = await stopped?.value
        XCTAssertFalse(heal.isActive)
        XCTAssertFalse(heal.isCurrent(second))
        XCTAssertNil(heal.pendingRestart)
        XCTAssertEqual(counter.count, 0)
    }

    // MARK: - Shuffle

    func testShuffleCapabilityAndErrors() throws {
        let capability = APIv2ShuffleCapability(state: "available", allowed: nil, scopeKinds: ["library", "series"])
        XCTAssertTrue(capability.isAvailable)
        XCTAssertTrue(capability.supports(.library))
        XCTAssertFalse(capability.supports(.season))
        XCTAssertFalse(APIv2ShuffleCapability(state: "available", allowed: false, scopeKinds: nil).isAvailable)
        XCTAssertFalse(APIv2ShuffleCapability(state: "available", allowed: true, scopeKinds: nil).supports(.library))

        XCTAssertEqual(ShuffleError.classify(APIv2Error.problem(try problem(404))), .notFound)
        XCTAssertEqual(ShuffleError.classify(APIv2Error.problem(try problem(409))), .nothingToPlay)
        XCTAssertNil(ShuffleError.classify(APIv2Error.problem(try problem(500))))
        XCTAssertNil(ShuffleError.classify(URLError(.timedOut)))
    }

    private func shuffleItem(_ id: String, type: String) -> String {
        #"{"content_id":"\#(id)","type":"\#(type)","title":"T \#(id)","poster_url":"/p.jpg","backdrop_url":"/b.jpg"}"#
    }

    func testShuffleScopeLabelAndUpcomingPick() throws {
        let season = try decode(APIv2Shuffle.self, """
        {"id":"s1","scope":{"kind":"season","id":"x","title":"Season 2","parent_title":"Breaking Bad"},
         "current":\(shuffleItem("a", type: "episode")),"next":\(shuffleItem("b", type: "episode"))}
        """)
        XCTAssertEqual(season.scopeLabel, "Breaking Bad · Season 2")
        XCTAssertEqual(season.upcoming?.contentId, "b")
        XCTAssertTrue(season.current.isEpisode)

        let single = try decode(APIv2Shuffle.self, """
        {"id":"s2","scope":{"kind":"library","id":"1","title":"Movies","parent_title":" "},
         "current":\(shuffleItem("m", type: "movie")),"next":\(shuffleItem("m", type: "movie"))}
        """)
        XCTAssertEqual(single.scopeLabel, "Movies")
        XCTAssertNil(single.upcoming)
        XCTAssertFalse(single.current.isEpisode)
    }

    // MARK: - Subtitle sync

    func testSubtitleSyncModels() {
        XCTAssertTrue(SubtitleTiming.identity.isIdentity)
        XCTAssertFalse(SubtitleTiming(offsetMs: 250, scale: 1).isIdentity)

        let running = SubtitleSyncJob(id: "j", subtitleId: nil, status: "running", trigger: "manual", confidence: nil,
                                      result: nil, createdAt: "2026-01-01T00:00:00Z", finishedAt: nil)
        XCTAssertTrue(running.isInProgress)
        XCTAssertNil(running.phase)
        XCTAssertNil(running.progress)
        XCTAssertNil(running.failure)
        let synced = SubtitleSyncJob(id: "k", subtitleId: "9", status: "synced", trigger: "auto", confidence: 0.9,
                                     result: SubtitleTiming(offsetMs: 120, scale: 1), createdAt: "c", finishedAt: "f")
        XCTAssertFalse(synced.isInProgress)

        let state = SubtitleSyncState(key: SubtitleSyncState.storedKey("9"), mediaFileId: "3", source: "downloaded",
                                      storedSubtitleId: "9", language: "en", format: "srt", label: "Release",
                                      timing: .identity, sync: nil)
        XCTAssertEqual(state.key, "stored-9")
        XCTAssertFalse(state.isExternal)
        let corrected = state.replacing(timing: SubtitleTiming(offsetMs: 120, scale: 1), sync: synced)
        XCTAssertEqual(corrected.timing.offsetMs, 120)
        XCTAssertEqual(corrected.sync, synced)
        XCTAssertEqual(corrected.replacing(sync: nil).timing.offsetMs, 120)

        let status = APIv2SubtitleSyncStatus(revision: "1", state: "available", allowed: true, autoSync: false,
                                             external: true)
        XCTAssertTrue(status.isAvailable)
        XCTAssertTrue(status.usesSyncKeys)
        let legacy = APIv2SubtitleSyncStatus(revision: "1", state: "available", allowed: false, autoSync: false,
                                             external: nil)
        XCTAssertFalse(legacy.isAvailable)
        XCTAssertFalse(legacy.usesSyncKeys)
    }

    // MARK: - Resume season / episode

    private func season(_ number: Int, specials: Bool = false, episodes: Int = 4, userData: String? = nil) -> String {
        let data = userData.map { #","user_data":\#($0)"# } ?? ""
        return #"{"content_id":"s\#(number)","season_number":\#(number),"is_specials":\#(specials),"episode_count":\#(episodes),"poster_url":"/p.jpg"\#(data)}"#
    }

    private func seasons(_ items: [String]) throws -> [Season] {
        try decode([Season].self, "[\(items.joined(separator: ","))]")
    }

    func testPreferredResumeSeason() throws {
        let inProgress = try seasons([season(1, userData: #"{"played":false,"in_progress_count":0}"#),
                                      season(2, userData: #"{"played":false,"in_progress_count":1}"#)])
        XCTAssertEqual(inProgress.preferredResumeSeason()?.contentId, "s2")

        let partial = try seasons([season(1, userData: #"{"played":true,"watched_count":4}"#),
                                   season(2, userData: #"{"played":false,"watched_count":2}"#)])
        XCTAssertEqual(partial.preferredResumeSeason()?.contentId, "s2")

        let fresh = try seasons([season(0, specials: true), season(1), season(2)])
        XCTAssertEqual(fresh.preferredResumeSeason()?.contentId, "s1")
        XCTAssertEqual(fresh.librarySeasonCount, 2)

        let specialsLeft = try seasons([season(0, specials: true),
                                        season(1, userData: #"{"played":true,"watched_count":4}"#)])
        XCTAssertEqual(specialsLeft.preferredResumeSeason()?.contentId, "s0")

        let allPlayed = try seasons([season(0, specials: true, userData: #"{"played":true,"watched_count":4}"#),
                                     season(1, userData: #"{"played":true,"watched_count":4}"#)])
        XCTAssertEqual(allPlayed.preferredResumeSeason()?.contentId, "s1")
        XCTAssertNil([Season]().preferredResumeSeason())

        XCTAssertTrue(PrairieMediaType.isSeason("Season"))
        XCTAssertTrue(PrairieMediaType.isSeason("seasons"))
        XCTAssertFalse(PrairieMediaType.isSeason("movie"))
    }

    private func episode(_ id: String, userData: String) -> String {
        #"{"content_id":"\#(id)","season_number":1,"episode_number":1,"still_url":"/s.jpg","user_data":\#(userData)}"#
    }

    func testPreferredResumeEpisode() throws {
        func episodes(_ items: [String]) throws -> [EpisodeListItem] {
            try decode([EpisodeListItem].self, "[\(items.joined(separator: ","))]")
        }
        let played = episode("e1", userData: #"{"played":true}"#)
        let resuming = episode("e2", userData: #"{"played":false,"is_in_progress":true}"#)
        let unplayed = episode("e3", userData: #"{"played":false}"#)
        XCTAssertEqual(try episodes([played, resuming, unplayed]).preferredResumeEpisode()?.contentId, "e2")
        XCTAssertEqual(try episodes([played, unplayed]).preferredResumeEpisode()?.contentId, "e3")
        XCTAssertEqual(try episodes([played]).preferredResumeEpisode()?.contentId, "e1")
        XCTAssertNil([EpisodeListItem]().preferredResumeEpisode())
    }

    func testSeasonsSortSpecialsFirstThenNumberTitleAndId() throws {
        let sorted = try decode([Season].self, """
        [{"content_id":"b","season_number":2,"title":"B","poster_url":"/p.jpg"},
         {"content_id":"a2","season_number":2,"title":"A","poster_url":"/p.jpg"},
         {"content_id":"a1","season_number":2,"title":"A","poster_url":"/p.jpg"},
         {"content_id":"one","season_number":1,"poster_url":"/p.jpg"},
         {"content_id":"sp","season_number":0,"is_specials":true,"poster_url":"/p.jpg"}]
        """).sortedForDisplay()
        XCTAssertEqual(sorted.map(\.contentId), ["sp", "one", "a1", "a2", "b"])
    }

    // MARK: - Snapshots and shuffle gating

    func testSnapshotStoreKeepsOnlyTheNewestSnapshotsPerScope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkingUpstreamGateFill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = ResponseSnapshotStore.Scope(serverId: "server-a", profileId: "adult")
        let extra = 2
        for libraryId in 0..<(ResponseSnapshotStore.maxSnapshotsPerScope + extra) {
            ResponseSnapshotStore.store(SectionsResponse(sections: []), forKey: CacheKey.librarySections(libraryId),
                                        scope: scope, in: root)
        }
        // load runs on the store's serial queue, after every write and trim.
        XCTAssertEqual(ResponseSnapshotStore.load(scope: scope, in: root).count,
                       ResponseSnapshotStore.maxSnapshotsPerScope)
    }

    func testShuffleIsNotOfferedBeforeTheCapabilityIsProbed() {
        let store = ShuffleFeatureStore()
        XCTAssertNil(store.capability)
        XCTAssertFalse(store.supports(.library))
    }

    // MARK: - Settings values

    func testRevisionGatedSettingMembers() {
        let key = SettingKey.playbackSubtitleAppearance
        XCTAssertEqual(key.revisionGatedMembers, ["textOpacity": SettingKey.subtitleTextOpacityRevision])
        XCTAssertTrue(SettingKey.catalogMetadataLanguage.revisionGatedMembers.isEmpty)

        let value = SettingJSONValue.object(["textOpacity": .double(0.5), "size": .int(2)])
        XCTAssertTrue(key.wireValue(value, forServerRevision: 13)
            .isSemanticallyEquivalent(to: .object(["size": .int(2)])))
        XCTAssertTrue(key.wireValue(value, forServerRevision: 14).isSemanticallyEquivalent(to: value))
        XCTAssertTrue(key.wireValue(.string("x"), forServerRevision: 1).isSemanticallyEquivalent(to: .string("x")))
    }

    func testSettingJSONValueSemanticEquivalence() {
        XCTAssertTrue(SettingJSONValue.null.isSemanticallyEquivalent(to: .null))
        XCTAssertTrue(SettingJSONValue.bool(true).isSemanticallyEquivalent(to: .bool(true)))
        XCTAssertTrue(SettingJSONValue.int(1).isSemanticallyEquivalent(to: .double(1.0)))
        XCTAssertTrue(SettingJSONValue.double(2.0).isSemanticallyEquivalent(to: .int(2)))
        XCTAssertFalse(SettingJSONValue.double(1.5).isSemanticallyEquivalent(to: .int(1)))
        XCTAssertTrue(SettingJSONValue.double(1.5).isSemanticallyEquivalent(to: .double(1.5)))
        XCTAssertTrue(SettingJSONValue.array([.int(1), .string("a")])
            .isSemanticallyEquivalent(to: .array([.double(1), .string("a")])))
        XCTAssertFalse(SettingJSONValue.array([.int(1)]).isSemanticallyEquivalent(to: .array([])))
        XCTAssertFalse(SettingJSONValue.object(["a": .int(1)]).isSemanticallyEquivalent(to: .object(["b": .int(1)])))
        XCTAssertFalse(SettingJSONValue.object(["a": .int(1)]).isSemanticallyEquivalent(to: .object([:])))
        XCTAssertFalse(SettingJSONValue.bool(true).isSemanticallyEquivalent(to: .string("true")))
    }

    // MARK: - Small models

    func testOnboardingProgressErrorDescriptions() {
        XCTAssertNotNil(OnboardingProgressError.tourChanged.errorDescription)
        XCTAssertNotNil(OnboardingProgressError.unexpectedReceipt.errorDescription)
        XCTAssertNotEqual(OnboardingProgressError.tourChanged.errorDescription,
                          OnboardingProgressError.unexpectedReceipt.errorDescription)
    }

    func testCatalogSearchFeaturesFromCapabilities() throws {
        XCTAssertEqual(CatalogSearchFeatures(), CatalogSearchFeatures(peopleMediaScope: false, videoWithEpisodesScope: false))
        let capabilities = try decode(APIv2CatalogSearchCapabilities.self,
                                      #"{"revision":"1","state":"available","allowed":true,"people_media_scope":true}"#)
        let features = CatalogSearchFeatures(capabilities)
        XCTAssertTrue(features.peopleMediaScope)
        XCTAssertFalse(features.videoWithEpisodesScope)
    }

    // MARK: - Response cache write fence

    func testResponseCacheWriteFenceAndPrefixInvalidation() {
        let cache = ResponseCache.shared
        let prefix = "gatefill:\(UUID().uuidString):"
        let key = prefix + "a"
        defer { cache.removeAll(withPrefix: prefix) }

        cache.set("v1", for: key, fetchedAt: cache.writeToken)
        XCTAssertEqual(cache.get(key, as: String.self), "v1")

        let before = cache.writeToken
        cache.remove(key)
        cache.set("stale", for: key, fetchedAt: before)
        XCTAssertNil(cache.get(key, as: String.self), "a response fetched before the invalidation is dropped")
        cache.set("fresh", for: key, fetchedAt: cache.writeToken)
        XCTAssertEqual(cache.get(key, as: String.self), "fresh")

        let beforePrefix = cache.writeToken
        cache.removeAll(withPrefix: prefix)
        XCTAssertNil(cache.get(key, as: String.self))
        cache.set("stale", for: prefix + "b", fetchedAt: beforePrefix)
        XCTAssertNil(cache.get(prefix + "b", as: String.self))

        cache.set("kept", for: prefix + "c")
        cache.clearMemory(withPrefix: prefix)
        XCTAssertNil(cache.get(prefix + "c", as: String.self))

        let contentId = "gatefill-\(UUID().uuidString)"
        cache.set("detail", for: CacheKey.itemDetail(contentId))
        cache.removeItemMetadata(contentId: contentId)
        XCTAssertNil(cache.get(CacheKey.itemDetail(contentId), as: String.self))

        XCTAssertEqual(CacheKey.catalogCollectionItems("c"), "collection:c:catalog:v2")
        cache.seedFromSnapshots()
    }

    // MARK: - 2026-10-18 merge: setting revisions, bitrate picker, artwork widths

    func testSubtitleSyncProfileScopeIsRevisionGated() {
        let key = SettingKey.playerSubtitleSyncMs
        XCTAssertEqual(key.profileScopeRevision, SettingKey.subtitleSyncProfileScopeRevision)
        XCTAssertFalse(key.acceptsProfileScope(atRevision: SettingKey.subtitleSyncProfileScopeRevision - 1))
        XCTAssertTrue(key.acceptsProfileScope(atRevision: SettingKey.subtitleSyncProfileScopeRevision))
        for other in SettingKey.allCases where other != key {
            XCTAssertNil(other.profileScopeRevision, other.rawValue)
            XCTAssertTrue(other.acceptsProfileScope(atRevision: 0), other.rawValue)
            XCTAssertEqual(other.isNewerThanMinimumServer, other.introducedIn > SettingKey.minimumServerRevision)
        }
    }

    func testBitratePickerLabelsAndKeepsAnUncoveredStoredCap() {
        XCTAssertEqual(PrairieQualityPresets.bitrateLabel(nil), PrairieQualityPresets.noBitrateLimitLabel)
        XCTAssertEqual(PrairieQualityPresets.bitrateLabel(0), PrairieQualityPresets.noBitrateLimitLabel)
        XCTAssertEqual(PrairieQualityPresets.bitrateLabel(8_000), ApplePlaybackQuality.formatBitrate(kbps: 8_000))

        let choices = PrairieQualityPresets.bitrateChoicesKbps
        XCTAssertEqual(PrairieQualityPresets.bitrateChoices(including: nil), choices)
        XCTAssertEqual(PrairieQualityPresets.bitrateChoices(including: choices[0]), choices)
        let custom = PrairieQualityPresets.bitrateChoices(including: 12_345)
        XCTAssertEqual(custom, (choices + [12_345]).sorted(by: >))
    }

    #if os(macOS)
    func testMacArtworkSlotsFollowTheContentColumn() {
        let display = ArtworkDisplay(scale: 2, screenSize: CGSize(width: 1840, height: 1000))
        // 1600 pt column; Home's hero is 0.8 x 1000 = 800 pt high.
        XCTAssertEqual(ArtworkSurface.home.slots(on: display).backdrop, 1600)
        XCTAssertEqual(ArtworkSurface.detail.slots(on: display).backdrop, 1600)
        XCTAssertEqual(ArtworkSurface.shelves.slots(on: display).backdrop, 340)
        XCTAssertEqual(ArtworkSurface.episodes.slots(on: display).still, 240)
        XCTAssertEqual(ArtworkSurface.seasons.slots(on: display).poster, 130)
        for surface in [ArtworkSurface.similar, .cards, .lists] {
            XCTAssertEqual(surface.slots(on: display).poster, 185)
        }
        XCTAssertNil(ArtworkSurface.watch.slots(on: display).poster)
        XCTAssertEqual(ArtworkSurface.shuffle.slots(on: display).imageSize, "medium")
        // A window narrower than the sidebar leaves a 0 pt column, so the
        // hero's height decides its width.
        let narrow = ArtworkDisplay(scale: 1, screenSize: CGSize(width: 100, height: 900))
        XCTAssertEqual(ArtworkSurface.detail.slots(on: narrow).backdrop, ArtworkSurface.fillWidth(CGSize(width: 0, height: 520)))
    }
    #endif
}
