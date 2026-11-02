import XCTest
@testable import Prairie

final class PrairieControlNowPlayingMetadataTests: XCTestCase {

    // MARK: - Wire

    /// Peers that predate the fields send frames without them.
    func testStateWithoutPosterOrOverviewDecodes() throws {
        let state = try Self.decodeState(extraKeys: "")
        XCTAssertNil(state.posterUrl)
        XCTAssertNil(state.overview)
    }

    func testStateCarriesPosterAndOverview() throws {
        let state = try Self.decodeState(
            extraKeys: #""posterUrl":"https://prairie.example/a.webp?exp=1&sig=x","overview":"Plot","#
        )
        XCTAssertEqual(state.posterUrl, "https://prairie.example/a.webp?exp=1&sig=x")
        XCTAssertEqual(state.overview, "Plot")
    }

    /// Unknown fields are left out rather than sent as null, so an older
    /// peer sees exactly the frame it saw before.
    func testUnknownMetadataIsOmittedFromTheWire() throws {
        var state = try Self.decodeState(extraKeys: "")
        XCTAssertNil(try Self.encodedState(state)["posterUrl"])
        XCTAssertNil(try Self.encodedState(state)["overview"])

        state.posterUrl = "https://prairie.example/p.webp"
        state.overview = "Plot"
        let json = try Self.encodedState(state)
        XCTAssertEqual(json["posterUrl"] as? String, "https://prairie.example/p.webp")
        XCTAssertEqual(json["overview"] as? String, "Plot")
    }

    /// A build that predates the fields decodes the state with Swift's
    /// synthesized decoder, which skips keys it doesn't declare.
    func testDecoderWithoutTheFieldsAcceptsNewFrames() throws {
        struct OlderState: Decodable { let title: String; let duration: Double }
        var state = try Self.decodeState(extraKeys: "")
        state.posterUrl = "https://prairie.example/p.webp"
        state.overview = "Plot"
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(OlderState.self, from: data).title, "Movie")
    }

    // MARK: - Choosing artwork

    func testEpisodeUsesSeriesPosterAndItsOwnOverview() throws {
        let episode = try Self.item(type: "episode", poster: "https://prairie.example/still.webp",
                                    overview: "Episode plot", seriesId: "series")
        let series = try Self.item(type: "series", poster: "https://prairie.example/series.webp",
                                   overview: "Series plot")
        let metadata = PrairieControlNowPlayingMetadata(item: episode, series: series)
        XCTAssertEqual(metadata.posterUrl, "https://prairie.example/series.webp")
        XCTAssertEqual(metadata.overview, "Episode plot")
    }

    /// The episode's own poster is its still, which may be a spoiler.
    func testEpisodeNeverSendsItsStill() throws {
        let episode = try Self.item(type: "episode", poster: "https://prairie.example/still.webp",
                                    overview: " ", seriesId: "series")
        let series = try Self.item(type: "series", poster: nil, overview: "Series plot")
        let metadata = PrairieControlNowPlayingMetadata(item: episode, series: series)
        XCTAssertNil(metadata.posterUrl)
        XCTAssertEqual(metadata.overview, "Series plot")
        XCTAssertNil(PrairieControlNowPlayingMetadata(item: episode, series: nil).posterUrl)
    }

    func testMovieUsesItsOwnPoster() throws {
        let movie = try Self.item(type: "movie", poster: "https://prairie.example/movie.webp", overview: "Plot")
        let metadata = PrairieControlNowPlayingMetadata(item: movie, series: nil)
        XCTAssertEqual(metadata.posterUrl, "https://prairie.example/movie.webp")
        XCTAssertEqual(metadata.overview, "Plot")
    }

    // MARK: - Expiry

    func testReadsPrairieAndS3Expiry() {
        XCTAssertEqual(
            PrairieControlArtworkExpiry.expiry(of: "https://prairie.example/api/v2/artwork/p.webp?exp=1700000000&sig=x"),
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(
            PrairieControlArtworkExpiry.expiry(
                of: "https://s3.example/p.webp?X-Amz-Date=20231114T221320Z&X-Amz-Expires=3600&X-Amz-Signature=x"
            ),
            Date(timeIntervalSince1970: 1_700_000_000 + 3600)
        )
        XCTAssertNil(PrairieControlArtworkExpiry.expiry(of: "https://cdn.example/p.webp"))
    }

    func testRefreshesAheadOfExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let url = "https://prairie.example/p.webp?exp=\(1_000_000 + 4 * 3600)&sig=x"
        XCTAssertEqual(PrairieControlArtworkExpiry.refreshDelay(for: url, now: now),
                       4 * 3600 - PrairieControlArtworkExpiry.refreshMargin)
        let stale = "https://prairie.example/p.webp?exp=\(1_000_000 - 10)&sig=x"
        XCTAssertEqual(PrairieControlArtworkExpiry.refreshDelay(for: stale, now: now),
                       PrairieControlArtworkExpiry.minimumRefresh)
        XCTAssertEqual(PrairieControlArtworkExpiry.refreshDelay(for: "https://cdn.example/p.webp", now: now),
                       PrairieControlArtworkExpiry.unknownExpiryRefresh)
        XCTAssertNil(PrairieControlArtworkExpiry.refreshDelay(for: nil, now: now))
    }

    // MARK: - Resolver

    @MainActor
    func testResolvesRefreshesAndClears() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var loads: [(String, Bool)] = []
        var changes = 0
        var signature = 0
        var sleeps: [TimeInterval] = []
        var releaseSleep: CheckedContinuation<Void, Never>?

        let resolver = PrairieControlNowPlayingMetadataResolver(
            load: { contentId, allowCached in
                loads.append((contentId, allowCached))
                signature += 1
                return PrairieControlNowPlayingMetadata(
                    posterUrl: "https://prairie.example/\(contentId).webp?exp=\(1_000_000 + 3600)&sig=\(signature)",
                    overview: "\(contentId) plot"
                )
            },
            now: { now },
            sleep: { delay in
                sleeps.append(delay)
                await withCheckedContinuation { releaseSleep = $0 }
            }
        )
        resolver.onChange = { changes += 1 }

        resolver.track(contentId: "a")
        XCTAssertNil(resolver.metadata(for: "a"), "nothing until the load finishes")
        try await waitUntil { changes == 1 }
        XCTAssertEqual(resolver.metadata(for: "a")?.overview, "a plot")
        XCTAssertTrue(resolver.metadata(for: "a")?.posterUrl?.hasSuffix("sig=1") == true)
        XCTAssertNil(resolver.metadata(for: "b"), "never reported for another title")
        XCTAssertEqual(sleeps, [3600 - PrairieControlArtworkExpiry.refreshMargin])

        // The refresh skips the cache and swaps in the re-signed URL.
        releaseSleep?.resume()
        try await waitUntil { changes == 2 }
        XCTAssertEqual(loads.last?.0, "a")
        XCTAssertEqual(loads.last?.1, false)
        XCTAssertTrue(resolver.metadata(for: "a")?.posterUrl?.hasSuffix("sig=2") == true)

        // A new title drops the old metadata at once.
        resolver.track(contentId: "b")
        XCTAssertNil(resolver.metadata(for: "a"))
        XCTAssertNil(resolver.metadata(for: "b"))
        try await waitUntil { changes == 3 }
        XCTAssertEqual(resolver.metadata(for: "b")?.overview, "b plot")

        // Playback stopping clears it.
        resolver.track(contentId: nil)
        XCTAssertNil(resolver.metadata(for: "b"))
        XCTAssertNil(resolver.contentId)
    }

    @MainActor
    func testExpiredPosterIsWithheldUntilReSigned() async throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        var changed = false
        let resolver = PrairieControlNowPlayingMetadataResolver(
            load: { _, _ in
                PrairieControlNowPlayingMetadata(
                    posterUrl: "https://prairie.example/p.webp?exp=\(1_000_000 + 60)&sig=x", overview: "Plot"
                )
            },
            now: { now },
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        resolver.onChange = { changed = true }
        resolver.track(contentId: "a")
        try await waitUntil { changed }
        XCTAssertNotNil(resolver.metadata(for: "a")?.posterUrl)

        now = now.addingTimeInterval(120)
        XCTAssertNil(resolver.metadata(for: "a")?.posterUrl)
        XCTAssertEqual(resolver.metadata(for: "a")?.overview, "Plot")
        resolver.track(contentId: nil)
    }

    // MARK: - Helpers

    private struct NotAState: Error {}

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition())
    }

    private static func item(type: String, poster: String?, overview: String?,
                             seriesId: String? = nil) throws -> ItemDetail {
        var fields: [String: Any] = ["content_id": UUID().uuidString, "type": type, "title": "Title"]
        fields["poster_url"] = poster
        fields["overview"] = overview
        fields["series_id"] = seriesId
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ItemDetail.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    private static func decodeState(extraKeys: String) throws -> PrairieControlPlaybackState {
        let json = """
        {"type":"state","v":2,"state":{
        "contentId":"c1","title":"Movie","isPlaying":true,"isLoading":false,
        "isBuffering":false,"currentTime":10.0,"duration":100.0,
        "audioTracks":[],"subtitleTracks":[],"qualityOptions":[],
        "activeQualityId":"auto","isQualitySwitching":false,"playbackSpeed":1.0,
        "videoGravity":"fit","hdrEnabled":false,"supportsVideoGravity":true,
        \(extraKeys)
        "volume":1.0,"isMuted":false,"hasNextEpisode":false}}
        """
        guard case .state(let state) = try JSONDecoder().decode(PrairieControlMessage.self, from: Data(json.utf8)) else {
            throw NotAState()
        }
        return state
    }

    private static func encodedState(_ state: PrairieControlPlaybackState) throws -> [String: Any] {
        let data = try JSONEncoder().encode(PrairieControlMessage.state(state))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["state"] as? [String: Any])
    }
}
