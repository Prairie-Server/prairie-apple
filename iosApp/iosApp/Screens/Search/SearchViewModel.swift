import Foundation

enum SearchMediaType: String, CaseIterable, Identifiable {
    case all
    case movie
    case series

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .movie: "Movies"
        case .series: "Series"
        }
    }

    var queryValue: String? {
        switch self {
        case .all: nil
        case .movie: "movie"
        case .series: "series"
        }
    }
}

@Observable
class SearchViewModel {
    var query = ""
    var selectedMediaType: SearchMediaType = .all
    var results: [BrowseItem] = []
    var isSearching = false
    var error: ErrorState?
    var hasSearched = false
    var hasMore = false
    var total = 0

    private var searchTask: Task<Void, Never>?
    private let pageSize = 60
    private var offset = 0

    /// Debounced search triggered on query change.
    func onQueryChanged() {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            resetState()
            return
        }

        searchTask = Task {
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(reset: true)
        }
    }

    func applyMediaType() async {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        await performSearch(reset: true)
    }

    func loadMore() async {
        guard hasMore, !isSearching else { return }
        await performSearch(reset: false)
    }

    func performSearch(reset: Bool = true) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            resetState()
            return
        }

        if !reset, !hasMore {
            return
        }

        let requestOffset = reset ? 0 : offset

        isSearching = true
        error = nil

        do {
            var searchQuery: [String: String] = [
                "source": "query",
                "q": trimmed,
                "limit": String(pageSize),
                "offset": String(requestOffset),
            ]
            if let mediaType = selectedMediaType.queryValue {
                searchQuery["type"] = mediaType
            }

            let response: CatalogResponse = try await ContinuumAPI.shared.get(
                "/api/v1/catalog",
                query: searchQuery
            )
            guard !Task.isCancelled else { return }

            if reset {
                results = response.items
            } else {
                let existingIds = Set(results.map(\.contentId))
                results.append(contentsOf: response.items.filter { !existingIds.contains($0.contentId) })
            }

            offset = requestOffset + response.items.count
            total = response.total ?? results.count
            hasMore = response.hasMore ?? false
            hasSearched = true
        } catch let err {
            guard !Task.isCancelled else { return }
            self.error = ErrorState(err)
            if reset {
                results = []
                total = 0
                hasMore = false
                hasSearched = true
            }
        }
        isSearching = false
    }

    private func resetState() {
        results = []
        isSearching = false
        error = nil
        hasSearched = false
        hasMore = false
        total = 0
        offset = 0
    }
}
