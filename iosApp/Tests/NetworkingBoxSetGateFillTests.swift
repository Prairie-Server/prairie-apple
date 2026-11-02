//
//  NetworkingBoxSetGateFillTests.swift
//  PrairieNetworkingTests
//
//  Closes coverage gaps the 2026-11-02 upstream merge introduced in the thin
//  Networking host: movie box sets (BoxSetModels, APIv2Client+BoxSets), whose
//  upstream suite (BoxSetTests) drives BoxSetDetailViewModel and
//  SearchViewModel and so runs only in the app bundles; the playback
//  connection and bandwidth-probe wire models; section catalog queries; and
//  the theme-music and row-limit edges upstream's own suites leave out.
//

import XCTest
import Foundation
@testable import Prairie

@MainActor
final class NetworkingBoxSetGateFillTests: XCTestCase {
    private static let catalogPath = "/api/v2/catalog"
    private static let boxSetPath = "/api/v2/catalog/box-sets/1241"
    private static let boxSetSearchPath = "/api/v2/catalog/box-sets"
    private static let searchCapabilitiesPath = "/api/v2/catalog/search/capabilities"

    private let harryPotter = #"{"id":"1241","library_id":"1","title":"Harry Potter Collection","overview":"Wizards.","poster_url":"/api/v2/artwork/tmdb/collections/1241/poster/w300.webp","poster_thumbhash":"x/cF","movie_count":8,"played_count":3,"first_year":2001,"last_year":2011}"#
    private let notFound = #"{"type":"https://prairieserver.org/docs/api/v2/problems/not_found","title":"Not found","status":404,"detail":"Not found","instance":"urn:test"}"#

    private var stub = APIv2TestStub()

    override func setUp() async throws {
        try await super.setUp()
        stub = APIv2TestStub()
    }

    private func api() async throws -> PrairieAPI {
        let name = "NetworkingBoxSetGateFillTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let tokens = TokenStore(keychain: SharedKeychain(service: name, accessGroup: nil),
            defaults: SharedDefaults(suite: suite, standard: suite))
        await tokens.switchActiveServer(serverId: "box-set-gate")
        await tokens.setServerUrl("https://boxsets.example")
        await tokens.setProfileId("profile-one")
        let http = HTTPClient(session: stub.makeSession(), tokenStore: tokens)
        return PrairieAPI(http: http, tokenStore: tokens)
    }

    private func movie(_ id: String, _ title: String, year: Int, played: Bool) -> String {
        #"{"content_id":"\#(id)","type":"movie","title":"\#(title)","year":\#(year),"user_state":{"played":\#(played),"is_favorite":false,"in_watchlist":false}}"#
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HTTPClient.makeJSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func boxSet(
        played: Int,
        count: Int = 3,
        first: Int? = 2001,
        last: Int? = 2004,
        libraryId: String = "4"
    ) -> CatalogBoxSet {
        CatalogBoxSet(id: "77", libraryId: libraryId, title: "Trilogy", overview: "Three films.",
                      movieCount: count, playedCount: played, firstYear: first, lastYear: last)
    }

    // MARK: - BoxSetModels

    func testBoxSetLibraryIdYearsAndCounts() {
        XCTAssertEqual(boxSet(played: 0).appLibraryId, 4)
        XCTAssertNil(boxSet(played: 0, libraryId: "0").appLibraryId, "a non-positive id is not addressable")
        XCTAssertNil(boxSet(played: 0, libraryId: "lib-x").appLibraryId)

        XCTAssertEqual(boxSet(played: 0).yearsText, "2001 – 2004")
        XCTAssertEqual(boxSet(played: 0, first: 1999, last: 1999).yearsText, "1999")
        XCTAssertEqual(boxSet(played: 0, first: nil, last: 2010).yearsText, "2010")
        XCTAssertEqual(boxSet(played: 0, first: 0, last: 0).yearsText, nil, "zero years read as absent")
        XCTAssertNil(boxSet(played: 0, first: nil, last: nil).yearsText)

        XCTAssertEqual(CatalogBoxSet.filmCount(1), "1 film")
        XCTAssertEqual(CatalogBoxSet.filmCount(5), "5 films")
        XCTAssertEqual(boxSet(played: 0, count: 3).filmCountText, "3 films")
    }

    func testBoxSetProgressCaptionAndAccessibilityLabel() throws {
        XCTAssertNil(boxSet(played: 0).watchedProgress)
        XCTAssertNil(boxSet(played: 2, count: 0).watchedProgress, "no films, no progress")
        XCTAssertEqual(try XCTUnwrap(boxSet(played: 1, count: 4).watchedProgress), 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(boxSet(played: 9, count: 3).watchedProgress), 1, accuracy: 0.0001,
                       "progress never runs past the whole set")

        XCTAssertEqual(boxSet(played: 2, count: 3).cardCaption, "2 / 3 watched")
        XCTAssertEqual(boxSet(played: 0).cardCaption, "2001 – 2004")
        XCTAssertEqual(boxSet(played: 0, count: 1, first: nil, last: nil).cardCaption, "1 film")

        XCTAssertEqual(boxSet(played: 0, first: nil, last: nil).accessibilityLabel,
                       "Trilogy, Box set of 3 films")
        XCTAssertEqual(boxSet(played: 1).accessibilityLabel,
                       "Trilogy, Box set of 3 films, 2001 – 2004, 1 of 3 watched")
    }

    private func item(_ id: String, played: Bool) -> BrowseItem {
        BrowseItem(
            contentId: id, type: "movie", title: "Film \(id)", year: nil, genres: nil, contentRating: nil,
            advisoryAge: nil, advisorySource: nil, status: nil, ratingImdb: nil, ratingTmdb: nil,
            ratingRtCritic: nil, ratingRtAudience: nil, runtime: nil, originalLanguage: nil,
            studios: nil, networks: nil, showStatus: nil, overview: nil, posterThumbhash: nil,
            backdropThumbhash: nil, addedAt: nil, releaseDate: nil, lastAirDate: nil,
            userState: MediaItemUserState(played: played), overlaySummary: nil
        )
    }

    func testBoxSetDetailPicksTheNextMovieAndLabelsPlay() {
        let fresh = CatalogBoxSetDetail(boxSet: boxSet(played: 0),
                                        items: [item("a", played: false), item("b", played: false)])
        XCTAssertEqual(fresh.nextMovie?.contentId, "a")
        XCTAssertFalse(fresh.isStarted)
        XCTAssertEqual(fresh.playVerb, "Play")
        XCTAssertEqual(fresh.playLabel, "Play Film a")
        XCTAssertEqual(fresh.factTokens, ["3 films", "2001 – 2004"])

        let started = CatalogBoxSetDetail(boxSet: boxSet(played: 1),
                                          items: [item("a", played: true), item("b", played: false)])
        XCTAssertEqual(started.nextMovie?.contentId, "b")
        XCTAssertTrue(started.isStarted)
        XCTAssertEqual(started.playVerb, "Continue")
        XCTAssertEqual(started.playLabel, "Continue · Film b")
        XCTAssertEqual(started.factTokens, ["3 films", "2001 – 2004", "1 of 3 watched"])

        let finished = CatalogBoxSetDetail(boxSet: boxSet(played: 3, first: nil, last: nil),
                                           items: [item("a", played: true), item("b", played: true)])
        XCTAssertEqual(finished.nextMovie?.contentId, "a", "a finished set starts over")
        XCTAssertFalse(finished.isStarted)
        XCTAssertEqual(finished.factTokens, ["3 films", "3 of 3 watched"])

        let empty = CatalogBoxSetDetail(boxSet: boxSet(played: 0), items: [])
        XCTAssertNil(empty.nextMovie)
        XCTAssertNil(empty.playLabel)
    }

    func testBoxSetWireShapesDecode() throws {
        let detail = try decode(CatalogBoxSetDetail.self, String(harryPotter.dropLast())
            + #","items":[\#(movie("hp1", "Stone", year: 2001, played: true))]}"#)
        XCTAssertEqual(detail.boxSet.id, "1241")
        XCTAssertEqual(detail.boxSet.libraryId, "1")
        XCTAssertEqual(detail.boxSet.title, "Harry Potter Collection")
        XCTAssertEqual(detail.boxSet.overview, "Wizards.")
        XCTAssertEqual(detail.boxSet.posterThumbhash, "x/cF")
        XCTAssertEqual(detail.boxSet.movieCount, 8)
        XCTAssertEqual(detail.boxSet.playedCount, 3)
        XCTAssertEqual(detail.boxSet.firstYear, 2001)
        XCTAssertEqual(detail.boxSet.lastYear, 2011)
        XCTAssertEqual(detail.items.map(\.contentId), ["hp1"])

        let wrapped = try decode(CatalogItemBoxSet.self, #"{"box_set":"# + String(harryPotter.dropLast())
            + #","items":[]}}"#)
        XCTAssertEqual(wrapped.boxSet?.boxSet.id, "1241")
        XCTAssertEqual(wrapped.boxSet?.items.count, 0)
        XCTAssertNil(try decode(CatalogItemBoxSet.self, "{}").boxSet)

        let list = try decode(CatalogBoxSetList.self, #"{"items":[\#(harryPotter)]}"#)
        XCTAssertEqual(list.items.map(\.id), ["1241"])
    }

    func testSearchResultLiftsIntoABoxSetCard() {
        let set = boxSet(played: 1)
        let card = BrowseItem(boxSet: set)
        XCTAssertEqual(card.contentId, "box_set:77")
        XCTAssertEqual(card.type, "box_set")
        XCTAssertEqual(card.title, "Trilogy")
        XCTAssertEqual(card.year, 2001)
        XCTAssertEqual(card.overview, "Three films.")
        XCTAssertEqual(card.boxSet?.id, "77")
        XCTAssertTrue(card.isBoxSet)
        XCTAssertFalse(item("a", played: false).isBoxSet, "a movie card is not a box set")
    }

    // MARK: - APIv2Client+BoxSets over the stub

    func testBoxSetReadSendsTheLibraryAndDecodesReleaseOrder() async throws {
        let api = try await api()
        let body = String(harryPotter.dropLast())
            + #","items":[\#(movie("hp1", "Stone", year: 2001, played: true)),\#(movie("hp2", "Chamber", year: 2002, played: false))]}"#
        stub.reply(path: Self.boxSetPath, 200, body)

        let detail = try await api.boxSet(id: "1241", libraryId: 1)

        let request = try XCTUnwrap(stub.requests.last { $0.path == Self.boxSetPath })
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.query["library_id"], "1")
        XCTAssertEqual(request.header("x-profile-id"), "profile-one")
        XCTAssertEqual(detail.items.map(\.contentId), ["hp1", "hp2"])
        XCTAssertEqual(detail.nextMovie?.contentId, "hp2")
        XCTAssertEqual(detail.playLabel, "Continue · Chamber")
    }

    func testBoxSetReadOfAnotherSetIsRefused() async throws {
        let api = try await api()
        let other = harryPotter.replacingOccurrences(of: #""id":"1241""#, with: #""id":"999""#)
        stub.reply(path: Self.boxSetPath, 200, String(other.dropLast()) + #","items":[]}"#)

        do {
            _ = try await api.boxSet(id: "1241", libraryId: 1)
            XCTFail("a box set answered under another id must not be shown")
        } catch {
            guard case APIv2Error.incompleteCatalogRead = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testBoxSetReadOfAnUnservedSetThrows() async throws {
        let api = try await api()
        stub.reply(path: Self.boxSetPath, 404, notFound)
        do {
            _ = try await api.boxSet(id: "1241", libraryId: 1)
            XCTFail("a 404 box set read must throw")
        } catch {}
        XCTAssertEqual(stub.requests.filter { $0.path == Self.boxSetPath }.count, 1)
    }

    func testItemBoxSetReadsTheSetOrNoneAndToleratesA404() async throws {
        let api = try await api()
        stub.reply(path: Self.searchCapabilitiesPath, 200,
                   #"{"revision":"r","state":"available","allowed":true,"box_sets":true}"#)
        let path = "/api/v2/catalog/items/hp1/box-set"
        let inSet = #"{"box_set":"# + String(harryPotter.dropLast())
            + #","items":[\#(movie("hp1", "Stone", year: 2001, played: false))]}}"#
        stub.sequence(path: path, [.json(200, inSet), .json(200, "{}"), .json(404, notFound)])

        let found = try await api.itemBoxSet(contentId: "hp1", libraryId: 3)
        XCTAssertEqual(found?.boxSet.id, "1241")
        XCTAssertEqual(found?.items.map(\.contentId), ["hp1"])
        XCTAssertEqual(stub.requests.last { $0.path == path }?.query["library_id"], "3")

        let none = try await api.itemBoxSet(contentId: "hp1", libraryId: nil)
        XCTAssertNil(none)
        XCTAssertNil(stub.requests.last { $0.path == path }?.query["library_id"])

        let missing = try await api.itemBoxSet(contentId: "hp1", libraryId: nil)
        XCTAssertNil(missing, "a 404 reads as no box set")
        XCTAssertEqual(stub.requestedPaths.filter { $0 == path }.count, 3)
        XCTAssertEqual(stub.requestedPaths.filter { $0 == Self.searchCapabilitiesPath }.count, 1,
                       "a server that said yes is not asked again")
    }

    func testItemBoxSetSkipsAServerWithoutBoxSets() async throws {
        let api = try await api()
        stub.reply(path: Self.searchCapabilitiesPath, 200, #"{"revision":"r","state":"available","allowed":true}"#)
        let path = "/api/v2/catalog/items/hp1/box-set"
        stub.reply(path: path, 200, "{}")

        let none = try await api.itemBoxSet(contentId: "hp1", libraryId: 1)

        XCTAssertNil(none)
        XCTAssertFalse(stub.requestedPaths.contains(path))
    }

    func testBoxSetSearchSendsTheQueryAndLimit() async throws {
        let api = try await api()
        stub.reply(path: Self.boxSetSearchPath, 200, #"{"items":[\#(harryPotter)]}"#)

        let sets = try await api.searchBoxSets(query: "potter", limit: 6)

        let request = try XCTUnwrap(stub.requests.last { $0.path == Self.boxSetSearchPath })
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.query["q"], "potter")
        XCTAssertEqual(request.query["limit"], "6")
        XCTAssertEqual(sets.map(\.id), ["1241"])
        XCTAssertEqual(sets.first?.cardCaption, "3 / 8 watched")
    }

    func testLibrariesReportWhetherTheyGroupBoxSets() async throws {
        let api = try await api()
        stub.reply(path: "/api/v2/user/libraries", 200, #"{"items":[{"id":"1","name":"Movies","type":"movies","sort_order":1,"box_sets_enabled":true},{"id":"2","name":"Films","type":"movies","sort_order":2,"box_sets_enabled":false},{"id":"3","name":"Old","type":"movies","sort_order":3}]}"#)

        let libraries = try await api.libraries().libraries

        XCTAssertEqual(libraries.map(\.browsesBoxSets), [true, false, false])
    }

    // MARK: - Catalog list page and section queries

    func testCatalogPageKeepsBoxSetCardsBesideMovies() async throws {
        let api = try await api()
        stub.reply(path: Self.catalogPath, 200, #"{"items":[\#(movie("movie-1", "Arrival", year: 2016, played: false)),{"content_id":"box_set:1241","type":"box_set","title":"Harry Potter Collection","year":2001,"user_state":{"played":false,"is_favorite":false,"in_watchlist":false},"box_set":\#(harryPotter)}],"page":{"has_more":false},"total":2,"total_exact":true}"#)

        let page = try await api.catalogPage(APIv2CatalogQuery.search("potter", type: "movie", limit: 10))

        let request = try XCTUnwrap(stub.requests.last { $0.path == Self.catalogPath })
        XCTAssertEqual(request.query["q"], "potter")
        XCTAssertEqual(page.response.items.map(\.contentId), ["movie-1", "box_set:1241"])
        XCTAssertEqual(page.response.items.map(\.isBoxSet), [false, true])
        XCTAssertEqual(page.response.items[1].boxSet?.appLibraryId, 1)
        XCTAssertNil(page.continuation, "the last page has no continuation")
        XCTAssertFalse(page.startsOver)
    }

    func testSectionItemsQueryNamesTheRowAndItsScope() {
        let home = APIv2CatalogQuery.sectionItems(
            SectionCatalogTarget(scope: .home, sectionId: "recent", title: "Recent"), limit: 40)
        XCTAssertEqual(home.source, "section")
        XCTAssertEqual(home.sectionId, "recent")
        XCTAssertEqual(home.scope, "home")
        XCTAssertNil(home.libraryId)
        XCTAssertEqual(home.limit, 40)

        let library = APIv2CatalogQuery.sectionItems(
            SectionCatalogTarget(scope: .library(7), sectionId: "genre-drama", title: "Drama"), limit: 20)
        XCTAssertEqual(library.source, "section")
        XCTAssertEqual(library.sectionId, "genre-drama")
        XCTAssertEqual(library.scope, "library")
        XCTAssertEqual(library.libraryId, "7")
        XCTAssertEqual(library.limit, 20)
    }

    // MARK: - Playback connection and bandwidth probe

    func testPlaybackConnectionDecodesProbeAndSampleLeniently() throws {
        let full = try decode(APIv2PlaybackConnection.self, #"{"connection":"local","probe":{"kbps":120000,"measured_at":"2026-10-17T19:02:11Z","transport":"ethernet","lower_bound":true},"playback_sample":{"kbps":9000,"measured_at":"2026-10-17T19:05:00Z"},"auto_budget_kbps":96000}"#)
        XCTAssertEqual(full.connection, "local")
        XCTAssertNil(full.learnedLimit)
        XCTAssertEqual(full.probe?.kbps, 120_000)
        XCTAssertEqual(full.probe?.transport, "ethernet")
        XCTAssertEqual(full.probe?.lowerBound, true)
        XCTAssertEqual(full.probe?.measuredAt, ISO8601DateFormatter().date(from: "2026-10-17T19:02:11Z"))
        XCTAssertEqual(full.playbackSample?.kbps, 9_000)
        XCTAssertEqual(full.playbackSample?.measuredAt, ISO8601DateFormatter().date(from: "2026-10-17T19:05:00Z"))
        XCTAssertEqual(full.autoBudgetKbps, 96_000)

        let plain = try decode(APIv2PlaybackConnection.self, #"{"connection":"remote","probe":{"kbps":800,"measured_at":"2026-10-17T19:02:11Z","transport":"cellular"},"playback_sample":"later"}"#)
        XCTAssertEqual(plain.probe?.lowerBound, false, "an absent lower_bound is false")
        XCTAssertEqual(plain.probe?.transport, "cellular")
        XCTAssertNil(plain.playbackSample, "a malformed optional member reads as absent")
        XCTAssertNil(plain.autoBudgetKbps)

        XCTAssertThrowsError(try decode(APIv2PlaybackConnection.self, #"{"probe":null}"#),
                             "connection is required")
    }

    private func encodedObject(_ result: APIv2PlaybackBandwidthProbeResult) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(result)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testBandwidthProbeResultSendsFlagsOnlyWhenTrue() throws {
        let quick = APIv2PlaybackBandwidthProbeResult(kbps: 4_000, bytes: 500_000, durationMs: 1_000,
                                                      transport: "wifi", lowerBound: false)
        XCTAssertNil(quick.lowerBound)
        XCTAssertNil(quick.manual)
        let quickBody = try encodedObject(quick)
        XCTAssertEqual(quickBody["kbps"] as? Int, 4_000)
        XCTAssertEqual(quickBody["bytes"] as? Int, 500_000)
        XCTAssertEqual(quickBody["duration_ms"] as? Int, 1_000)
        XCTAssertEqual(quickBody["transport"] as? String, "wifi")
        XCTAssertNil(quickBody["lower_bound"], "false is the default and is never sent")
        XCTAssertNil(quickBody["manual"])

        let manual = APIv2PlaybackBandwidthProbeResult(kbps: 90_000, bytes: 1_000_000_000, durationMs: 9_000,
                                                       transport: "ethernet", lowerBound: true, manual: true)
        XCTAssertEqual(manual.lowerBound, true)
        XCTAssertEqual(manual.manual, true)
        let manualBody = try encodedObject(manual)
        XCTAssertEqual(manualBody["lower_bound"] as? Bool, true)
        XCTAssertEqual(manualBody["manual"] as? Bool, true)
    }

    // MARK: - Models edges

    func testCommunityRatingLabelAndSubtitleFormatSupport() throws {
        XCTAssertEqual(CommunityRating(average: 4.0, count: 1).label, "4.0 · 1 rating")
        XCTAssertEqual(CommunityRating(average: 3.5, count: 7).label, "3.5 · 7 ratings")

        XCTAssertTrue(try decode(SubtitleTrack.self, #"{"index":3,"codec":" "}"#).hasUnsupportedFormat,
                      "an embedded track stored without a codec cannot be delivered")
        XCTAssertTrue(try decode(SubtitleTrack.self, #"{"index":4}"#).hasUnsupportedFormat)
        XCTAssertFalse(try decode(SubtitleTrack.self, #"{"index":5,"codec":"subrip"}"#).hasUnsupportedFormat)
        XCTAssertFalse(try decode(SubtitleTrack.self, #"{"external":true}"#).hasUnsupportedFormat,
                       "a sidecar is converted by the server")
    }

    // MARK: - Theme music and row-limit edges

    func testThemeMusicSettingAndWriteFailureMessages() {
        let setting = ThemeMusicSetting(enabled: true, loop: false)
        XCTAssertTrue(setting.enabled)
        XCTAssertFalse(setting.loop)
        XCTAssertNotEqual(setting, ThemeMusicSetting(enabled: true, loop: true))

        XCTAssertTrue(ThemeMusicPreferences.writeFailureMessage(
            for: SettingsAPIError.transport(description: "offline")).contains("connection"))
        XCTAssertEqual(ThemeMusicPreferences.writeFailureMessage(for: SettingsAPIError.serverUpgradeRequired),
                       "This server can't save the theme music setting.")
        XCTAssertEqual(ThemeMusicPreferences.writeFailureMessage(
            for: SettingsAPIError.unknownSetting(key: "ui.theme_music_loop")),
                       "This server can't save the theme music setting.")
        XCTAssertEqual(ThemeMusicPreferences.writeFailureMessage(
            for: SettingsAPIError.server(status: 500, code: nil, message: nil)),
                       "The server didn't save the theme music setting. Try again.")
    }

    func testThemeMusicWithoutAnIdentityStaysOffAndResetForgets() async throws {
        let api = try await api()
        let store = ThemeMusicPreferences(transport: PrairieTitleArtTransport(api: api), requestIdentity: { nil })

        await store.refresh()
        XCTAssertFalse(store.isOffered)
        XCTAssertFalse(store.playsThemeMusic)
        XCTAssertFalse(store.loops)
        XCTAssertFalse(store.allowsEditing)
        XCTAssertTrue(stub.requests.isEmpty, "no identity, no settings read")

        store.setEnabled(true)
        XCTAssertFalse(store.playsThemeMusic, "nothing to write before an answer")
        store.reset()
        XCTAssertFalse(store.isOffered)
        XCTAssertNil(store.errorMessage)
    }

    func testRowLimitSupportRemembersTheAdvertisedMaximumInUserDefaults() {
        let serverID = "gate-fill-\(UUID().uuidString)"
        let key = "sectionItemLimitMax.v1.\(serverID)"
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: key) }

        SectionItemLimitSupport(memory: .userDefaults).record(100, serverID: serverID)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), 100)
        XCTAssertEqual(SectionItemLimitSupport(memory: .userDefaults).itemLimit(serverID: serverID), 20,
                       "a fresh launch reads the remembered maximum, capped to a row")

        SectionItemLimitSupport(memory: .userDefaults).record(0, serverID: serverID)
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "no maximum forgets the server")
        XCTAssertNil(SectionItemLimitSupport(memory: .userDefaults).itemLimit(serverID: serverID))
    }

    // MARK: - Settings error vocabulary

    func testSettingsErrorUnknownKeyAnswerAndJSONNull() {
        XCTAssertTrue(SettingsAPIError.unknownSetting(key: "ui.theme_music_enabled").isUnknownKeyAnswer)
        XCTAssertTrue(SettingsAPIError.serverUpgradeRequired.isUnknownKeyAnswer)
        XCTAssertFalse(SettingsAPIError.ownerChanged.isUnknownKeyAnswer)
        XCTAssertFalse(SettingsAPIError.transport(description: "offline").isUnknownKeyAnswer)

        XCTAssertTrue(SettingJSONValue.null.isNull)
        XCTAssertFalse(SettingJSONValue.bool(false).isNull)
        XCTAssertFalse(SettingJSONValue.string("").isNull)
    }

    // MARK: - TokenStore profile selection

    func testProfileSelectionGenerationFollowsTheProfileSwitch() async throws {
        let name = "NetworkingBoxSetGateFillTests.tokens.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let tokens = TokenStore(keychain: SharedKeychain(service: name, accessGroup: nil),
            defaults: SharedDefaults(suite: suite, standard: suite))
        await tokens.switchActiveServer(serverId: "generation-server")
        await tokens.setServerUrl("https://generation.example")
        await tokens.setProfileId("profile-one")

        let captured = await tokens.captureOrdinaryRequestAuth()
        let auth = try XCTUnwrap(captured)
        let read = await tokens.profileSelectionGeneration(matchingIdentityOf: auth)
        let generation = try XCTUnwrap(read, "the captured identity is still current")
        let isCurrent = await tokens.isCurrentProfileSelection(generation)
        XCTAssertTrue(isCurrent)
        let isStranger = await tokens.isCurrentProfileSelection(UUID())
        XCTAssertFalse(isStranger)

        await tokens.setProfileId("profile-two")

        let stale = await tokens.isCurrentProfileSelection(generation)
        XCTAssertFalse(stale, "a profile switch installs a new selection")
        let afterSwitch = await tokens.profileSelectionGeneration(matchingIdentityOf: auth)
        XCTAssertNil(afterSwitch, "the old profile's capture no longer matches")
    }

    // MARK: - Carried track picks (host-side twin of the player-bridge suites)

    private func fileVersion(_ json: String) throws -> FileVersion {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FileVersion.self, from: Data(json.utf8))
    }

    private func watchDetail(version: FileVersion) -> WatchDetail {
        WatchDetail(
            contentId: "ep-2", type: "episode", title: "Two", year: nil, overview: nil,
            versions: [version], subtitles: nil, intro: nil, credits: nil, userData: nil,
            seriesId: "series-9", seriesTitle: nil, seasonNumber: 1, episodeNumber: 2,
            effectiveSubtitleLanguage: nil, effectiveSubtitleMode: "auto",
            effectiveShowForcedSubtitles: nil, effectiveSubtitleTrackSignature: nil
        )
    }

    func testUntaggedSubtitlePickIsCarriedOnlyWhenItsTitleIdentifiesIt() throws {
        let version = try fileVersion("""
        {
          "file_id": 6,
          "subtitle_tracks": [
            { "index": 2, "language": "und", "codec": "subrip", "title": "Full dialogue" },
            { "index": 3, "codec": "ass", "title": "Signs & Songs" }
          ]
        }
        """)
        let titled = SubtitlePrefRequest(
            subtitleLanguage: "und", subtitleTrackIndex: 3, externalSubtitlePath: "", subtitleMode: "always",
            trackSignature: SubtitleTrackSignature(source: "embedded", language: "und", codec: "ass", label: "Signs & Songs")
        )
        let carried = TrackSelectionPersistence.Settlement(rereads: false, unsettled: [.subtitle: .subtitle(titled)])
            .applied(to: watchDetail(version: version))
        XCTAssertNil(carried.effectiveSubtitleLanguage, "`und` names no language")
        XCTAssertEqual(carried.effectiveSubtitleMode, "always")
        let signature = try XCTUnwrap(carried.effectiveSubtitleTrackSignature)
        XCTAssertEqual(signature.source, "embedded")
        XCTAssertNil(signature.language, "an undefined language would match any other `und` track")
        XCTAssertEqual(signature.codec, "ass")
        XCTAssertEqual(signature.label, "Signs & Songs")

        let unnamed = SubtitlePrefRequest(
            subtitleLanguage: "", subtitleTrackIndex: 3, externalSubtitlePath: "", subtitleMode: "always",
            trackSignature: SubtitleTrackSignature(source: "embedded", language: nil, codec: "ass", label: "Commentary")
        )
        let kept = TrackSelectionPersistence.Settlement(rereads: false, unsettled: [.subtitle: .subtitle(unnamed)])
            .applied(to: watchDetail(version: version))
        XCTAssertEqual(kept.effectiveSubtitleMode, "auto", "an unidentifiable pick leaves the server's state")
        XCTAssertNil(kept.effectiveSubtitleTrackSignature)
    }

    func testAudioPickFallsBackToItsOrdinalThenTheFirstTrackInItsLanguage() throws {
        let version = try fileVersion("""
        {
          "file_id": 7,
          "audio_tracks": [
            { "index": 1, "language": "jpn", "codec": "aac", "channels": 2 },
            { "index": 2, "language": "eng", "codec": "aac", "channels": 2 },
            { "index": 3, "language": "eng", "codec": "ac3", "channels": 6 }
          ]
        }
        """)
        func ordinal(_ index: Int, _ language: String) -> Int? {
            TrackSelectionPersistence.audioOrdinal(
                matching: AudioPrefRequest(audioTrackIndex: index, audioLanguage: language, trackSignature: nil),
                in: version)
        }
        XCTAssertEqual(ordinal(2, "en"), 2, "its own ordinal when that track has the language")
        XCTAssertEqual(ordinal(0, "en"), 1, "else the first track in the language")
        XCTAssertEqual(ordinal(9, "eng"), 1)
        XCTAssertNil(ordinal(0, "fr"), "no track in the language leaves the server's choice")

        let applied = TrackSelectionPersistence.Settlement(rereads: false, unsettled: [
            .audio: .audio(AudioPrefRequest(audioTrackIndex: 0, audioLanguage: "en", trackSignature: nil)),
        ]).applied(to: watchDetail(version: version))
        XCTAssertEqual(applied.versions[0].effectiveAudioTrackIndex, 1)
        XCTAssertEqual(applied.versions[0].effectiveAudioLanguage, "eng")
    }

    // MARK: - ServerRegistry origin matching

    func testSameOriginInAnotherSpellingKeepsTheSavedIdentity() throws {
        let name = "NetworkingBoxSetGateFillTests.registry.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let defaults = SharedDefaults(suite: suite, standard: suite)
        let keychain = SharedKeychain.inMemory(service: name)
        let registry = ServerRegistry(
            defaults: defaults,
            keychain: keychain,
            launchPreferences: ProfileLaunchPreferences(defaults: defaults),
            persistenceOverride: { _, _ in true },
            tokenStore: TokenStore(keychain: keychain, defaults: defaults),
            httpClient: HTTPClient(session: StubURLProtocol.Handler().makeSession())
        )
        let savedURL = "https://home.example"
        let savedId = ServerRegistry.serverId(for: savedURL)
        registry.addOrUpdate(ServerEntry(id: savedId, url: savedURL, fetchedName: "Home",
                                         lastUsedAt: Date(), verifiedServerId: "srv-home"))

        let spelledURL = "HTTPS://HOME.example:443"
        let spelledId = ServerRegistry.serverId(for: spelledURL)
        XCTAssertNotEqual(spelledId, savedId)
        let merged = try XCTUnwrap(registry.addOrUpdate(
            ServerEntry(id: spelledId, url: spelledURL, fetchedName: "Home Server", lastUsedAt: Date())))

        XCTAssertEqual(merged.id, savedId, "the saved id keys its credentials")
        XCTAssertEqual(merged.url, savedURL)
        XCTAssertEqual(merged.fetchedName, "Home Server")
        XCTAssertEqual(merged.verifiedServerId, "srv-home", "an unverified update keeps the verified identity")
        XCTAssertEqual(registry.entries.map(\.id), [savedId])
        XCTAssertEqual(registry.entry(matching: spelledId)?.id, savedId)
        XCTAssertEqual(registry.entry(matching: savedId)?.fetchedName, "Home Server")
        XCTAssertNil(registry.entry(matching: ServerRegistry.serverId(for: "https://other.example")))
    }
}
