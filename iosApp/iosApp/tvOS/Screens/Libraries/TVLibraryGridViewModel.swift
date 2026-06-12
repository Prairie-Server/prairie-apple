#if os(tvOS)
import Foundation
import Observation

/// Filter state that can be pre-applied to the grid from the landing page or
/// the alphabet rail. Equatable so the grid can compare generations.
struct TVLibraryFilter: Equatable {
    var namePrefix: String? = nil
    var genre: String? = nil
    var yearMin: Int? = nil
    var yearMax: Int? = nil
    var sort: String = "title"

    static let none = TVLibraryFilter()
}

/// View model backing the tvOS library grid. Purpose-built for 100k-item
/// libraries; does not share state with the iOS `BrowseViewModel`.
///
/// Key differences from iOS:
///
/// - **Pagination** uses the server's snapshot timestamp (`snapshot_at`) as a
///   fence so pages stay coherent even if items are being ingested mid-scroll.
///   The first response's `snapshot` is captured and forwarded on every
///   subsequent page.
/// - **Page size** is 100 (the server's hard cap) instead of 60 — tvOS grids
///   have far more cells visible per scroll.
/// - **Prefetch trigger** fires at 25% remaining (4 rows of a 6-column grid)
///   rather than the iOS "last 6 items" heuristic, which on tvOS translates
///   to only one row of lead time.
/// - **Filter state** (letter prefix, genre, sort) resets pagination when
///   changed; any in-flight fetch is implicitly superseded by a generation
///   counter.
@Observable
@MainActor
final class TVLibraryGridViewModel {
    // MARK: - Observable state

    var items: [BrowseItem] = []
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var error: ErrorState? = nil
    var hasMore: Bool = true
    private(set) var filter: TVLibraryFilter

    // MARK: - Private state

    private let libraryId: Int
    private let mediaType: String?
    private let pageSize: Int = 100

    /// Server-returned snapshot timestamp. Captured from the first page and
    /// forwarded on subsequent pages so the server returns a stable window
    /// even if catalog content changes mid-scroll.
    private var snapshot: String? = nil
    private var nextOffset: Int = 0
    private var prefetchedPosterURLs: Set<URL> = []

    /// Incremented whenever filters change. In-flight requests from a prior
    /// generation discard their results instead of appending stale data.
    private var generation: Int = 0

    init(libraryId: Int, libraryType: String, initialFilter: TVLibraryFilter = .none) {
        self.libraryId = libraryId
        self.mediaType = Self.mediaTypeFor(libraryType: libraryType)
        self.filter = initialFilter
        hydratePage1FromCache()
    }

    private var currentCacheKey: String {
        CacheKey.tvLibrary(libraryId: libraryId, filterKey: filterKey)
    }

    private var filterKey: String {
        let prefix = filter.namePrefix ?? "all"
        let genre = filter.genre ?? "all"
        let yMin = filter.yearMin.map(String.init) ?? "any"
        let yMax = filter.yearMax.map(String.init) ?? "any"
        return "\(prefix):\(genre):\(yMin):\(yMax):\(filter.sort)"
    }

    private func hydratePage1FromCache() {
        guard items.isEmpty,
              let cached: CatalogResponse = ResponseCache.shared.get(currentCacheKey) else {
            return
        }
        items = cached.items
        hasMore = cached.hasMore ?? false
        nextOffset = cached.items.count
        snapshot = cached.snapshot
    }

    /// Map server library `type` ("movies" / "series") to the catalog
    /// endpoint's `type` param ("movie" / "series"). Audiobook and music
    /// libraries omit the param entirely — `library_id` already scopes the
    /// query, and the catalog's `type` vocabulary only covers video (this
    /// matches the iOS browse path, which never sends `type`).
    private static func mediaTypeFor(libraryType: String) -> String? {
        switch libraryType {
        case "series", "shows", "tv": return "series"
        default:
            if SiloMediaType.isAudiobook(libraryType) || libraryType == "music" {
                return nil
            }
            return "movie"
        }
    }

    // MARK: - Public API

    /// Initial fetch for the current filter state. Safe to call repeatedly;
    /// no-ops while already loading.
    func loadInitial() async {
        await reload()
    }

    /// Load the next page of items if available and not already loading.
    func loadMoreIfNeeded() async {
        guard hasMore, !isLoading else { return }
        await fetchPage(reset: false)
    }

    /// Jump to a name prefix (A–Z + "#" for non-alpha). Resets pagination.
    func jumpToPrefix(_ letter: String?) async {
        filter.namePrefix = letter
        await reload()
    }

    /// Replace the full filter set (e.g. from a landing-page tap). Resets
    /// pagination and snapshot.
    func applyFilter(_ newFilter: TVLibraryFilter) async {
        guard newFilter != filter else { return }
        filter = newFilter
        await reload()
    }

    /// Enqueue upcoming poster URLs on the shared Nuke prefetcher. The view
    /// layer calls this when cells near the trailing edge appear.
    func prefetchPosters(in range: Range<Int>) {
        let urls = items[safe: range]
            .compactMap { $0.posterUrl }
            .compactMap { URL(string: $0) }
        let newURLs = urls.filter { prefetchedPosterURLs.insert($0).inserted }
        guard !newURLs.isEmpty else { return }
        PosterImageCache.prefetcher.startPrefetching(with: newURLs)
    }

    /// Cancel prefetch for URLs no longer near the visible window.
    func cancelPrefetch(in range: Range<Int>) {
        let urls = items[safe: range]
            .compactMap { $0.posterUrl }
            .compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return }
        urls.forEach { prefetchedPosterURLs.remove($0) }
        PosterImageCache.prefetcher.stopPrefetching(with: urls)
    }

    // MARK: - Fetch logic

    private func reload() async {
        if !prefetchedPosterURLs.isEmpty {
            PosterImageCache.prefetcher.stopPrefetching(with: Array(prefetchedPosterURLs))
            prefetchedPosterURLs.removeAll()
        }
        generation += 1
        items = []
        nextOffset = 0
        hasMore = true
        snapshot = nil
        error = nil
        hydratePage1FromCache()
        await fetchPage(reset: true)
    }

    private func fetchPage(reset: Bool) async {
        let myGeneration = generation
        if reset, !items.isEmpty {
            isRefreshing = true
        } else {
            isLoading = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        var query: [String: String] = [
            "source": "query",
            "library_id": String(libraryId),
            "offset": String(nextOffset),
            "limit": String(pageSize),
            "sort": filter.sort,
        ]
        if let mediaType { query["type"] = mediaType }
        if let namePrefix = filter.namePrefix { query["name_prefix"] = namePrefix }
        if let genre = filter.genre { query["genre"] = genre }
        if let yearMin = filter.yearMin { query["year_min"] = String(yearMin) }
        if let yearMax = filter.yearMax { query["year_max"] = String(yearMax) }
        if let snapshot { query["snapshot_at"] = snapshot }

        do {
            let response: CatalogResponse = try await ContinuumAPI.shared.get(
                "/api/v1/catalog", query: query
            )

            // Discard if another reload superseded us while we awaited.
            guard myGeneration == generation else { return }

            if reset {
                items = response.items
                ResponseCache.shared.set(response, for: currentCacheKey)
            } else {
                items.append(contentsOf: response.items)
            }
            hasMore = response.hasMore ?? false
            nextOffset += response.items.count
            if snapshot == nil { snapshot = response.snapshot }
        } catch {
            guard myGeneration == generation else { return }
            if items.isEmpty {
                self.error = ErrorState(error)
            }
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe range: Range<Int>) -> ArraySlice<Element> {
        let lower = Swift.max(0, range.lowerBound)
        let upper = Swift.min(count, range.upperBound)
        guard lower < upper else { return [] }
        return self[lower..<upper]
    }
}
#endif
