import Network
import XCTest
@testable import Prairie

final class PrairieControlTests: XCTestCase {
    private func roundTrip(_ message: PrairieControlMessage) throws -> PrairieControlMessage {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(PrairieControlMessage.self, from: data)
    }

    func testPingPongRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.ping), .ping)
        XCTAssertEqual(try roundTrip(.pong), .pong)
    }

    func testVolumeMuteNextCommandsRoundTrip() throws {
        let setVol = PrairieControlCommand.setVolume(0.4)
        XCTAssertEqual(try roundTrip(.control(setVol)), .control(setVol))
        let mute = PrairieControlCommand.setMuted(true)
        XCTAssertEqual(try roundTrip(.control(mute)), .control(mute))
        XCTAssertEqual(try roundTrip(.control(.playNext)), .control(.playNext))
    }

    func testProtocolNegotiatesHighestCommonVersion() {
        XCTAssertEqual(PrairieControlProtocol.negotiatedVersion(with: [1]), 1)
        XCTAssertEqual(PrairieControlProtocol.negotiatedVersion(with: [1, 2]), 2)
        XCTAssertNil(PrairieControlProtocol.negotiatedVersion(with: [3]))
    }

    func testRemoteIdentityHandoffMessagesRoundTrip() throws {
        let offer = PrairieControlHandoffOffer(
            requestId: "request-1",
            serverId: "server-1",
            serverURL: "https://prairie.example",
            serverName: "Home",
            profileId: "profile-1",
            profileName: "Alex"
        )
        let challenge = PrairieControlHandoffChallenge(
            requestId: "request-1",
            userCode: "ABCD-EFGH",
            matchCode: "WXYZ",
            expiresAt: "2026-07-09T20:00:00Z"
        )
        let ready = PrairieControlHandoffReady(
            requestId: "request-1",
            serverId: "server-1",
            profileId: "profile-1",
            sessionExpiresAt: "2026-07-10T20:00:00Z",
            reused: false
        )
        let cancel = PrairieControlHandoffCancel(
            requestId: "request-1",
            reason: "denied",
            message: "The handoff was denied."
        )

        XCTAssertEqual(try roundTrip(.handoffOffer(offer)), .handoffOffer(offer))
        XCTAssertEqual(try roundTrip(.handoffChallenge(challenge)), .handoffChallenge(challenge))
        XCTAssertEqual(try roundTrip(.handoffReady(ready)), .handoffReady(ready))
        XCTAssertEqual(try roundTrip(.handoffCancel(cancel)), .handoffCancel(cancel))
    }

    /// The phone approves only the request the TV challenged with: same
    /// match code, opened for remote playback, ending in a temporary session.
    /// A full device sign-in with the same code is never approved here.
    @MainActor func testHandoffApprovesOnlyATemporaryRemotePlaybackRequest() {
        let challenge = PrairieControlHandoffChallenge(requestId: "request-1", userCode: "ABCD-1234",
            matchCode: "42", expiresAt: "2026-01-02T03:14:05Z")
        func lookup(match: String = "42", purpose: String = "remote_playback", temporary: Bool = true) -> DeviceLookupResponse {
            DeviceLookupResponse(matchCode: match, deviceName: "TV", devicePlatform: "tvos", status: "pending",
                clientPurpose: purpose, temporary: temporary)
        }
        XCTAssertTrue(PrairieControlClient.isRemotePlaybackHandoff(lookup(), answering: challenge))
        XCTAssertFalse(PrairieControlClient.isRemotePlaybackHandoff(lookup(match: "43"), answering: challenge))
        XCTAssertFalse(PrairieControlClient.isRemotePlaybackHandoff(lookup(purpose: "device_login"), answering: challenge))
        XCTAssertFalse(PrairieControlClient.isRemotePlaybackHandoff(lookup(temporary: false), answering: challenge))
    }

    func testHandoffOfferDecodesWithoutDisplayMetadata() throws {
        let data = Data(
            #"{"type":"handoff_offer","v":2,"handoffOffer":{"requestId":"request-1","serverId":"server-1","serverURL":"https://prairie.example","profileId":"profile-1"}}"#
                .utf8
        )
        guard case .handoffOffer(let offer) = try JSONDecoder().decode(PrairieControlMessage.self, from: data) else {
            return XCTFail("Expected a handoff offer")
        }
        XCTAssertNil(offer.serverName)
        XCTAssertNil(offer.profileName)
    }

    func testHandoffOfferCarriesIdentityAndEndpointsOptionally() throws {
        let offer = PrairieControlHandoffOffer(
            requestId: "request-1",
            serverId: "server-1",
            serverURL: "https://prairie.overlay.example",
            serverName: "Home",
            profileId: "profile-1",
            profileName: "Alex",
            serverIdentity: "96c1bd08-b839-4d47-980e-57d4e7a44cfa",
            serverEndpoints: [
                ServerEndpoint(url: "https://prairie.example", kind: .public),
                ServerEndpoint(url: "https://prairie.overlay.example", kind: .provider, provider: "tailscale", displayName: "Tailscale"),
            ]
        )
        XCTAssertEqual(try roundTrip(.handoffOffer(offer)), .handoffOffer(offer))

        let hello = PrairieControlHello(
            role: .tv, deviceName: "TV", deviceId: "tv-1", serverId: "server-1", serverName: "Home",
            supportedVersions: [1, 2], serverIdentity: "96c1bd08-b839-4d47-980e-57d4e7a44cfa"
        )
        XCTAssertEqual(try roundTrip(.hello(hello)), .hello(hello))

        // The keys stay off the wire when unset, so a v2 peer that predates
        // them never sees an unexpected value.
        let legacyOffer = PrairieControlHandoffOffer(
            requestId: "r", serverId: "s", serverURL: "https://prairie.example",
            serverName: nil, profileId: "p", profileName: nil
        )
        let data = try JSONEncoder().encode(PrairieControlMessage.handoffOffer(legacyOffer))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try XCTUnwrap(json["handoffOffer"] as? [String: Any])
        XCTAssertNil(body["serverIdentity"])
        XCTAssertNil(body["serverEndpoints"])
    }

    func testServerIdentityMatchesURLCapitalizationAcrossDevices() {
        let phone = ServerRegistry.serverId(for: "https://Media.Example.test")
        let tv = ServerRegistry.serverId(for: "HTTPS://media.example.test/")

        XCTAssertNotEqual(phone, tv, "persisted registry keys remain unchanged")
        XCTAssertTrue(ServerRegistry.serverIdsMatch(phone, tv))
    }

    func testServerIdentityMatchesDefaultPortsButNotDifferentOrigins() {
        let canonical = ServerRegistry.serverId(for: "https://media.example.test/library")
        let explicitDefault = ServerRegistry.serverId(for: "https://MEDIA.example.test:443/library/")
        let otherPort = ServerRegistry.serverId(for: "https://media.example.test:8443/library")
        let otherScheme = ServerRegistry.serverId(for: "http://media.example.test/library")
        let pathCase = ServerRegistry.serverId(for: "https://media.example.test/Library")

        XCTAssertTrue(ServerRegistry.serverIdsMatch(canonical, explicitDefault))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(canonical, otherPort))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(canonical, otherScheme))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(canonical, pathCase))
    }

    func testServerIdentityDecoderRequiresAValidRoundTrippingHTTPURL() {
        let original = "https://Média.example.test:443/prairie?mode=A#top"
        let serverId = ServerRegistry.serverId(for: original)

        XCTAssertEqual(ServerRegistry.url(forServerId: serverId), original)
        XCTAssertNil(ServerRegistry.url(forServerId: "not-a-registry-id"))
        XCTAssertNil(ServerRegistry.url(forServerId: ServerRegistry.serverId(for: "file:///tmp/prairie")))
        XCTAssertFalse(ServerRegistry.serverIdsMatch(nil, serverId))
        XCTAssertTrue(ServerRegistry.serverIdsMatch("future-format", "future-format"))
        XCTAssertFalse(ServerRegistry.serverIdsMatch("future-format-a", "future-format-b"))
    }
}

extension PrairieControlTests {
    @MainActor func testClockInterpolatesWhilePlaying() {
        let clock = RemotePlaybackClock()
        let t0 = Date(timeIntervalSince1970: 1000)
        clock.ingest(.fixture(), asOf: t0)
        XCTAssertEqual(clock.displayTime(asOf: t0.addingTimeInterval(3)), 3, accuracy: 0.01)
    }

    @MainActor func testClockClampsToDuration() {
        let clock = RemotePlaybackClock()
        let t0 = Date(timeIntervalSince1970: 1000)
        clock.ingest(.fixture(), asOf: t0)
        XCTAssertEqual(clock.displayTime(asOf: t0.addingTimeInterval(999)), 100, accuracy: 0.01)
    }

    @MainActor func testOptimisticPlayingWinsUntilConfirmed() {
        let clock = RemotePlaybackClock()
        let t0 = Date(timeIntervalSince1970: 1000)
        clock.ingest(.fixture(isPlaying: false), asOf: t0)
        clock.setOptimisticPlaying(true, asOf: t0)
        // Optimistic override wins within the window (evaluated against the
        // injected clock, not the wall clock).
        XCTAssertTrue(clock.isPlaying(asOf: t0))
        clock.ingest(.fixture(isPlaying: true), asOf: t0.addingTimeInterval(0.5))
        XCTAssertTrue(clock.isPlaying(asOf: t0.addingTimeInterval(0.5)))
    }

    @MainActor func testOptimisticSeekHoldsUntilSnapshotCatchesUp() {
        let clock = RemotePlaybackClock()
        let t0 = Date(timeIntervalSince1970: 1000)
        clock.ingest(.fixture(isPlaying: false, currentTime: 10), asOf: t0)
        // Scrub to 1200s; a stale snapshot still reporting ~10s must not snap
        // the scrubber back.
        clock.setOptimisticTime(1200, asOf: t0)
        clock.ingest(.fixture(isPlaying: false, currentTime: 10, duration: 3000),
                     asOf: t0.addingTimeInterval(0.5))
        XCTAssertEqual(clock.displayTime(asOf: t0.addingTimeInterval(0.5)), 1200, accuracy: 0.01)
        // Once the TV confirms the seek, the clock tracks it again.
        clock.ingest(.fixture(isPlaying: false, currentTime: 1200, duration: 3000),
                     asOf: t0.addingTimeInterval(1.0))
        XCTAssertEqual(clock.displayTime(asOf: t0.addingTimeInterval(1.0)), 1200, accuracy: 0.01)
    }
}

extension PrairieControlTests {
    func testHeldVolumeSurvivesAStaleReplyMidBurst() {
        var reconciler = RemoteVolumeReconciler()
        let t0 = Date(timeIntervalSince1970: 1000)
        // Two hardware steps before the TV answers either one.
        reconciler.requested(0.5625, at: t0)
        reconciler.requested(0.625, at: t0.addingTimeInterval(0.1))
        // The reply to the first step must not rewind the level, or the next
        // step would recompute 0.625 and the second press would be lost.
        XCTAssertEqual(reconciler.reconcile(inbound: 0.5625, at: t0.addingTimeInterval(0.2)),
                       0.625, accuracy: 0.0001)
        // Once the TV catches up, its value is authoritative again.
        XCTAssertEqual(reconciler.reconcile(inbound: 0.625, at: t0.addingTimeInterval(0.3)),
                       0.625, accuracy: 0.0001)
        XCTAssertEqual(reconciler.reconcile(inbound: 0.2, at: t0.addingTimeInterval(0.4)),
                       0.2, accuracy: 0.0001)
    }

    func testHeldVolumeIsReleasedWhenTheWindowLapses() {
        var reconciler = RemoteVolumeReconciler()
        let t0 = Date(timeIntervalSince1970: 1000)
        reconciler.requested(0.9, at: t0)
        // A dropped command, or a change made on the TV itself, must not leave
        // the remote showing a level the TV does not have.
        let lapsed = t0.addingTimeInterval(RemoteVolumeReconciler.window + 0.1)
        XCTAssertEqual(reconciler.reconcile(inbound: 0.3, at: lapsed), 0.3, accuracy: 0.0001)
    }

    func testMuteClearsTheHeldVolume() {
        var reconciler = RemoteVolumeReconciler()
        let t0 = Date(timeIntervalSince1970: 1000)
        reconciler.requested(0.9, at: t0)
        reconciler.clear()
        XCTAssertEqual(reconciler.reconcile(inbound: 0.3, at: t0.addingTimeInterval(0.1)),
                       0.3, accuracy: 0.0001)
    }
}

private extension PrairieControlPlaybackState {
    static func fixture(isPlaying: Bool = true, currentTime: Double = 0, duration: Double = 100,
                        playbackSpeed: Double = 1.0) -> PrairieControlPlaybackState {
        PrairieControlPlaybackState(
            contentId: "c", sessionId: nil, title: "T", subtitle: nil,
            isPlaying: isPlaying, isLoading: false, isBuffering: false,
            currentTime: currentTime, duration: duration,
            audioTracks: [], subtitleTracks: [],
            selectedAudioTrackId: nil, selectedSubtitleTrackId: nil,
            qualityOptions: [], activeQualityId: "auto", isQualitySwitching: false,
            playbackSpeed: playbackSpeed, videoGravity: "fit", hdrEnabled: false,
            supportsVideoGravity: false,
            volume: 1.0, isMuted: false, hasNextEpisode: false, nextEpisodeTitle: nil,
            error: nil)
    }
}

// MARK: - Several controllers on one TV (phone side)

final class PrairieControlPhoneMultiControllerTests: XCTestCase {
    func testOlderTVsCloseOnlyForATakeoverOrDisconnectSoThePhoneForgetsThem() {
        for reason in [nil, PrairieControlCloseReason.timeout, PrairieControlCloseReason.replaced] {
            XCTAssertEqual(
                PrairieControlClosePolicy.response(reason: reason, tvKeepsOtherControllers: false),
                .letGo(forgetTarget: true)
            )
        }
    }

    func testMultiControllerTVsSayWhyTheyClosed() {
        func response(_ reason: String?) -> PrairieControlCloseResponse {
            PrairieControlClosePolicy.response(reason: reason, tvKeepsOtherControllers: true)
        }
        XCTAssertEqual(response(PrairieControlCloseReason.timeout), .reconnect)
        XCTAssertEqual(response(PrairieControlCloseReason.tvDisconnected), .letGo(forgetTarget: true))
        XCTAssertEqual(response(nil), .letGo(forgetTarget: true))
        XCTAssertEqual(response(PrairieControlCloseReason.replaced), .letGo(forgetTarget: false))
        XCTAssertEqual(response(PrairieControlCloseReason.tooManyControllers), .letGo(forgetTarget: false))
        XCTAssertEqual(response("from_a_newer_tv"), .letGo(forgetTarget: false))
    }

    func testReplacePromptNamesWhoIsWatchingWhat() {
        let pending = PrairieControlPendingReplace(
            request: Self.request,
            nowPlaying: PrairieControlNowPlayingSummary(
                contentId: "e1", title: "Pilot", subtitle: "Severance · S1E1",
                profileName: "Alex", controllerName: nil
            ),
            tvName: "Living Room",
            fallbackMessage: "unused"
        )
        XCTAssertEqual(pending.message, "Alex is watching Severance · S1E1 · Pilot on Living Room. Play yours instead?")
    }

    func testReplacePromptFallsBackToTheTVsWording() {
        let pending = PrairieControlPendingReplace(
            request: Self.request, nowPlaying: nil, tvName: "Living Room",
            fallbackMessage: "Someone is watching a title on this TV."
        )
        XCTAssertEqual(pending.message, "Someone is watching a title on this TV.")
    }

    func testResumeTokenIsOfferedOnlyForTheSameTVServerAndProfile() {
        var tokens = PrairieControlResumeTokens()
        tokens.store("tok", tvId: "tv1", serverId: "srv", profileId: "alex")
        XCTAssertEqual(tokens.token(tvId: "tv1", serverId: "srv", profileId: "alex"), "tok")
        XCTAssertNil(tokens.token(tvId: "tv2", serverId: "srv", profileId: "alex"))
        XCTAssertNil(tokens.token(tvId: "tv1", serverId: "srv", profileId: "sam"))
        XCTAssertNil(tokens.token(tvId: "tv1", serverId: "other", profileId: "alex"))
    }

    /// A ready from an older TV carries no token and must not erase one.
    func testAMissingTokenKeepsTheStoredOne() {
        var tokens = PrairieControlResumeTokens()
        tokens.store("tok", tvId: "tv1", serverId: "srv", profileId: "alex")
        tokens.store(nil, tvId: "tv1", serverId: "srv", profileId: "alex")
        XCTAssertEqual(tokens.token(tvId: "tv1", serverId: "srv", profileId: "alex"), "tok")
    }

    /// The same words prairie-android's phone sends, so either TV shows the same "Starting" line.
    func testOfferTitleNamesAnEpisodeBySeriesAndNumber() {
        XCTAssertEqual(
            PrairieControlOfferTitle.make(type: "episode", title: "Pilot", seriesTitle: "Severance", seasonNumber: 1, episodeNumber: 2),
            "Severance · S1 · E2"
        )
        XCTAssertEqual(
            PrairieControlOfferTitle.make(type: "Episodes", title: "Pilot", seriesTitle: "Severance", seasonNumber: 1, episodeNumber: 2),
            "Severance · S1 · E2"
        )
        XCTAssertEqual(
            PrairieControlOfferTitle.make(type: "episode", title: "Pilot", seriesTitle: " ", seasonNumber: 1, episodeNumber: 2),
            "Pilot"
        )
        XCTAssertEqual(
            PrairieControlOfferTitle.make(type: "movie", title: "Oak Street", seriesTitle: "Ignored", seasonNumber: nil, episodeNumber: nil),
            "Oak Street"
        )
        XCTAssertNil(PrairieControlOfferTitle.make(type: "movie", title: "  ", seriesTitle: nil, seasonNumber: nil, episodeNumber: nil))
    }

    func testOfferTitleTravelsOnTheWireOnlyWhenSet() throws {
        let offer = PrairieControlHandoffOffer(
            requestId: "r", serverId: "s", serverURL: "https://prairie.example",
            serverName: nil, profileId: "p", profileName: nil, title: "Oak Street"
        )
        let data = try JSONEncoder().encode(PrairieControlMessage.handoffOffer(offer))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["handoffOffer"] as? [String: Any])?["title"] as? String, "Oak Street")

        var untitled = offer
        untitled.title = nil
        let bare = try JSONEncoder().encode(PrairieControlMessage.handoffOffer(untitled))
        let bareJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: bare) as? [String: Any])
        XCTAssertNil((bareJSON["handoffOffer"] as? [String: Any])?["title"])
    }

    @MainActor func testHandshakeRecordsTheTVsFeatures() {
        let handshake = PrairieControlHandshake()
        XCTAssertFalse(handshake.tvSupports(PrairieControlFeature.presence))
        handshake.receive(.hello(PrairieControlHello(
            role: .tv, deviceName: "Living Room", deviceId: "tv1", serverId: "srv", serverName: nil,
            supportedVersions: [2], features: [PrairieControlFeature.presence]
        )))
        XCTAssertTrue(handshake.tvSupports(PrairieControlFeature.presence))
        XCTAssertFalse(handshake.tvSupports(PrairieControlFeature.multiController))
    }

    @MainActor func testReplaceRefusalSurfacesWhatIsPlaying() async {
        let handshake = PrairieControlHandshake()
        let nowPlaying = PrairieControlNowPlayingSummary(
            contentId: "c1", title: "Dune", subtitle: nil, profileName: "Alex", controllerName: nil
        )
        handshake.beginHandoff(requestId: "r1")
        handshake.receive(.handoffCancel(PrairieControlHandoffCancel(
            requestId: "r1",
            reason: PrairieControlHandoffCancelReason.replaceConfirmationRequired,
            message: "Alex is watching Dune on this TV.",
            nowPlaying: nowPlaying
        )))
        do {
            _ = try await handshake.firstReply(to: "r1", within: .seconds(1))
            XCTFail("expected a replace refusal")
        } catch {
            XCTAssertEqual(
                error as? PrairieControlHandoffError,
                .replaceConfirmationRequired(nowPlaying, message: "Alex is watching Dune on this TV.")
            )
        }
    }

    @MainActor func testOtherRefusalsStayPlainCancellations() async {
        let handshake = PrairieControlHandshake()
        handshake.beginHandoff(requestId: "r1")
        handshake.receive(.handoffCancel(PrairieControlHandoffCancel(
            requestId: "r1", reason: PrairieControlHandoffCancelReason.superseded, message: "Sam started playing."
        )))
        do {
            _ = try await handshake.firstReply(to: "r1", within: .seconds(1))
            XCTFail("expected a cancellation")
        } catch {
            XCTAssertEqual(error as? PrairieControlHandoffError, .cancelled("Sam started playing."))
        }
    }

    private static let request = PrairieControlPlaybackRequest(
        contentId: "c2", fileId: nil, audioTrackIndex: nil, subtitleTrackIndex: nil,
        startFromBeginning: false, resumePosition: nil
    )
}

/// Finding and dialing a Roku (prairie-roku `docs/prairiecontrol.md` sections 4.4,
/// 5.1 and 5.3).
final class PrairieControlRokuTargetTests: XCTestCase {
    private let endpoint = NWEndpoint.hostPort(host: "192.168.1.20", port: 52817)

    private func rokuTXT(_ extra: [String: String] = [:]) -> [String: String] {
        ["v": "2", "name": "Den Roku", "id": "roku-1", "server": "c2VydmVy", "serverName": "Home", "playing": "0"]
            .merging(extra) { $1 }
    }

    func testARokuIsDialedAsItsTXTSays() throws {
        let plain = try XCTUnwrap(PrairieControlBrowser.makeTarget(txt: rokuTXT(), endpoint: endpoint,
            serviceType: PrairieControlProtocol.rokuServiceType))
        XCTAssertEqual(plain.transport, .plain)
        XCTAssertEqual(plain.name, "Den Roku")
        XCTAssertNil(plain.keyId)

        let sealed = try XCTUnwrap(PrairieControlBrowser.makeTarget(txt: rokuTXT(["sec": "sealed", "kid": "BE45CB26"]),
            endpoint: endpoint, serviceType: PrairieControlProtocol.rokuServiceType))
        XCTAssertEqual(sealed.transport, .sealed)
        XCTAssertEqual(sealed.keyId, "be45cb26")

        XCTAssertNil(PrairieControlBrowser.makeTarget(txt: rokuTXT(["sec": "sealed"]), endpoint: endpoint,
            serviceType: PrairieControlProtocol.rokuServiceType), "sealed without a key ID")
        XCTAssertNil(PrairieControlBrowser.makeTarget(txt: rokuTXT(["sec": "quantum"]), endpoint: endpoint,
            serviceType: PrairieControlProtocol.rokuServiceType), "a level this build can't speak")
    }

    /// Nothing in a `_prairiecast._tcp` TXT record moves a TV off TLS.
    func testATLSTVStaysOnTLSWhateverItsTXTSays() throws {
        let target = try XCTUnwrap(PrairieControlBrowser.makeTarget(txt: rokuTXT(["sec": "plain"]), endpoint: endpoint,
            serviceType: PrairieControlProtocol.serviceType))
        XCTAssertEqual(target.transport, .tls)
    }

    func testRokusAndOtherTVsShareOneListByName() {
        func target(_ id: String, _ name: String, _ transport: PrairieControlTransport) -> PrairieControlTarget {
            PrairieControlTarget(id: id, name: name, endpoint: endpoint, serverId: "s", serverName: nil,
                protocolVersion: 2, transport: transport)
        }
        let merged = PrairieControlBrowser.merged([
            PrairieControlProtocol.serviceType: [target("a", "Living Room", .tls)],
            PrairieControlProtocol.rokuServiceType: [target("b", "Bedroom", .plain), target("a", "Living Room", .plain)],
        ])
        XCTAssertEqual(merged.map(\.id), ["b", "a"])
        XCTAssertEqual(merged.last?.transport, .tls, "a device listed under both types keeps TLS")
    }

    func testReadsAPlainPairingLink() throws {
        let link = try XCTUnwrap(PrairieControlPairingLink(url: URL(string:
            "prairie://cast?v=2&host=192.168.1.20&port=52817&id=roku-1&name=Den%20Roku&server=c2VydmVy&security=plain&future=1")!))
        XCTAssertEqual(link.transport, .plain)
        XCTAssertNil(link.key)
        let target = link.target
        XCTAssertEqual(target.id, "roku-1")
        XCTAssertEqual(target.name, "Den Roku")
        XCTAssertEqual(target.serverId, "c2VydmVy")
        XCTAssertEqual(target.endpoint, .hostPort(host: .ipv4(IPv4Address("192.168.1.20")!), port: 52817))
        XCTAssertEqual(target.transport, .plain)
    }

    func testReadsASealedPairingLinksKey() throws {
        let link = try XCTUnwrap(PrairieControlPairingLink(url: URL(string:
            "prairie://cast?v=2&host=10.0.0.5&port=52818&id=roku-1&name=Den&server=c2VydmVy&security=sealed&key=AAAQEAYEAUDAOCAJBIFQYDIOB4")!))
        XCTAssertEqual(link.transport, .sealed)
        XCTAssertEqual(link.key?.count, 16)
        XCTAssertEqual(link.target.keyId, "be45cb26")
    }

    func testRefusesLinksARokuNeverShows() {
        func link(_ query: String) -> PrairieControlPairingLink? {
            PrairieControlPairingLink(url: URL(string: "prairie://cast?v=2&id=roku-1&server=s&\(query)")!)
        }
        XCTAssertNotNil(link("host=172.16.0.9&port=52817"))
        XCTAssertNotNil(link("host=169.254.3.4&port=52817"))
        XCTAssertNil(link("host=8.8.8.8&port=52817"), "a public address")
        XCTAssertNil(link("host=roku.example&port=52817"), "a host name")
        XCTAssertNil(link("host=172.32.0.1&port=52817"), "outside 172.16/12")
        XCTAssertNil(link("host=192.168.1.20&port=0"))
        XCTAssertNil(link("host=192.168.1.20&port=52817&security=sealed"), "sealed without a key")
        XCTAssertNil(link("host=192.168.1.20&port=52817&security=sealed&key=AAAA"), "a short key")
        XCTAssertNil(PrairieControlPairingLink(url: URL(string: "prairie://item/abc?host=192.168.1.20&port=1&id=r&server=s")!))
    }

    /// A Roku takes the server's combined subtitle ordinal (external tracks
    /// first); the phone picks by FFmpeg stream index.
    func testARokuLaunchCarriesTheServersSubtitleOrdinal() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let version = try decoder.decode(FileVersion.self, from: Data("""
        {
          "file_id": 7,
          "audio_tracks": [{ "index": 1, "codec": "aac" }, { "index": 2, "codec": "ac3" }],
          "subtitle_tracks": [
            { "index": 3, "codec": "subrip", "language": "eng" },
            { "codec": "srt", "language": "fra", "external": true, "external_path": "movie.fr.srt" },
            { "index": 5, "codec": "ass", "language": "spa" }
          ]
        }
        """.utf8))
        func launch(subtitle: Int?, audio: Int? = 1) -> PrairieControlPlaybackRequest {
            PrairieControlPlaybackRequest(contentId: "c", fileId: 7, audioTrackIndex: audio, subtitleTrackIndex: subtitle,
                startFromBeginning: false, resumePosition: 42, pinsVersion: true)
        }

        let converted = PrairieControlRokuLaunch.playback(launch(subtitle: 5), version: version)
        XCTAssertEqual(converted.subtitleTrackIndex, 2, "after one external and one earlier embedded track")
        XCTAssertEqual(converted.audioTrackIndex, 1, "the audio position is already the server's ordinal")
        XCTAssertEqual(converted.resumePosition, 42)
        XCTAssertEqual(converted.pinsVersion, true)
        XCTAssertEqual(PrairieControlRokuLaunch.playback(launch(subtitle: 3), version: version).subtitleTrackIndex, 1)
        XCTAssertEqual(PrairieControlRokuLaunch.playback(launch(subtitle: -1), version: version).subtitleTrackIndex, -1, "off")
        XCTAssertNil(PrairieControlRokuLaunch.playback(launch(subtitle: nil), version: version).subtitleTrackIndex)
        XCTAssertNil(PrairieControlRokuLaunch.playback(launch(subtitle: 9), version: version).subtitleTrackIndex,
            "a stream the version doesn't list")
        XCTAssertNil(PrairieControlRokuLaunch.playback(launch(subtitle: 5), version: nil).subtitleTrackIndex,
            "no track list to convert against")
    }

    /// A plain advertisement with a paired Roku's ID can't move it to plain
    /// TCP; only a new pairing link drops the key. Never a TLS TV.
    func testAPairedRokuStaysSealedWhenAdvertisedPlain() {
        func target(_ transport: PrairieControlTransport) -> PrairieControlTarget {
            PrairieControlTarget(id: "roku-1", name: "Den Roku", endpoint: endpoint, serverId: "s", serverName: nil,
                protocolVersion: 2, transport: transport)
        }
        let key = Data(repeating: 7, count: PrairieControlSealed.keyBytes)

        let pinned = PrairieControlPairingKeys.pinned(target(.plain), key: key)
        XCTAssertEqual(pinned.transport, .sealed)
        XCTAssertEqual(pinned.keyId, PrairieControlSealed.keyId(key))
        XCTAssertEqual(PrairieControlPairingKeys.pinned(target(.plain), key: nil), target(.plain), "never paired")
        XCTAssertEqual(PrairieControlPairingKeys.pinned(target(.tls), key: key), target(.tls))
    }

    /// The track list read for a Roku subtitle pick belongs to the server
    /// and profile the launch started under; a launch whose scope changed
    /// during the read stops instead of using it.
    @MainActor
    func testARokuLaunchStopsWhenTheScopeChangesDuringItsDetailRead() async throws {
        let request = PrairieControlPlaybackRequest(contentId: "roku-scope-\(UUID().uuidString)", fileId: 7,
            audioTrackIndex: 1, subtitleTrackIndex: 5, startFromBeginning: false, resumePosition: nil,
            pinsVersion: true)
        var scopeChanged = false
        var reads = 0
        let fetch: (String) async -> ItemDetail? = { _ in
            reads += 1
            scopeChanged = true
            return nil
        }
        do {
            _ = try await PrairieControlClient.rokuPlayback(request, fetchDetail: fetch, ensureIdentity: {
                if scopeChanged { throw PrairieControlHandoffError.identityChanged }
            })
            XCTFail("a launch whose scope changed mid-read must not continue")
        } catch PrairieControlHandoffError.identityChanged {
        }
        XCTAssertEqual(reads, 1)

        let unchanged = try await PrairieControlClient.rokuPlayback(request, fetchDetail: { _ in nil }, ensureIdentity: {})
        XCTAssertNil(unchanged.subtitleTrackIndex, "no track list to convert against")
    }

    func testOnlyARokuAsksToHavePrairieOpened() {
        let roku = PrairieControlTarget(id: "r", name: "Den Roku", endpoint: endpoint, serverId: "s", serverName: nil,
            protocolVersion: 2, transport: .plain)
        let appleTV = PrairieControlTarget(id: "a", name: "Living Room", endpoint: endpoint, serverId: "s",
            serverName: nil, protocolVersion: 2)
        XCTAssertEqual(PrairieControlClient.unreachableMessage(for: roku), "Couldn't reach Den Roku. Open Prairie on your Roku.")
        XCTAssertEqual(PrairieControlClient.unreachableMessage(for: appleTV), "Couldn't reach Living Room.")
    }
}
