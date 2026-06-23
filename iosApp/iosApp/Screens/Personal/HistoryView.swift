import SwiftUI

/// List of recently watched items from the user's history.
struct HistoryView: View {
    @State private var items: [BrowseItem] = []
    @State private var isLoading = false
    @State private var error: ErrorState?
    @State private var hasMore = true
    @State private var totalItems: Int?
    @State private var nextOffset = 0
    @State private var snapshot: String?
    @Environment(AppRouter.self) private var router

    private let pageSize = 60

    var body: some View {
        Group {
            if !items.isEmpty {
                gridContent
            } else if let error {
                ErrorView(state: error, onRetry: { Task { await loadHistory(reset: true) } })
            } else if isLoading {
                // tvOS: this is a pushed destination, so the top menu bar
                // isn't there to hold focus — without a focusable element
                // the remote goes dead until the grid renders.
                Color.clear
                #if os(tvOS)
                    .focusable()
                #endif
            } else {
                EmptyStateView(
                    icon: "clock",
                    title: "No watch history",
                    subtitle: "Items you watch will appear here"
                )
            }
        }
        .continuumBackground()
        .navigationTitle("History")
        .continuumNavigationTitleDisplayMode(.large)
        .task {
            await loadHistory(reset: true)
        }
        .refreshable {
            await loadHistory(reset: true)
        }
    }

    private var gridContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: ContinuumTheme.padding) {
                Text(countLabel)
                    .font(.continuumCaption)
                    .foregroundColor(.continuumSecondaryText)

                CatalogGrid(
                    items: items,
                    isLoading: isLoading,
                    hasMore: hasMore,
                    onItemTap: { contentId in
                        router.navigate(to: .itemDetail(contentId: contentId))
                    },
                    onLoadMore: {
                        Task { await loadMoreIfNeeded() }
                    }
                )
            }
            .padding(.horizontal, ContinuumTheme.padding)
            .padding(.top, ContinuumTheme.smallPadding)
            .padding(.bottom, ContinuumTheme.largePadding)
        }
    }

    private var countLabel: String {
        if let totalItems {
            return "\(totalItems) item\(totalItems == 1 ? "" : "s")"
        }
        let suffix = hasMore ? "+" : ""
        return "\(items.count)\(suffix) item\(items.count == 1 && !hasMore ? "" : "s")"
    }

    private func loadMoreIfNeeded() async {
        guard hasMore, !isLoading else { return }
        await loadHistory(reset: false)
    }

    private func loadHistory(reset: Bool) async {
        guard !isLoading else { return }
        if reset {
            if items.isEmpty,
               let cached: CatalogResponse = ResponseCache.shared.get(CacheKey.history) {
                items = cached.items
                hasMore = cached.hasMore ?? false
                totalItems = cached.totalExact == false ? nil : cached.total
                nextOffset = cached.items.count
                snapshot = cached.snapshot
            } else {
                hasMore = true
                nextOffset = 0
                snapshot = nil
            }
        }
        guard reset || hasMore else { return }

        isLoading = true
        error = nil
        let requestOffset = reset ? 0 : nextOffset
        let requestSnapshot = reset ? nil : snapshot
        do {
            let response = try await ContinuumAPI.shared.historyCatalog(
                offset: requestOffset,
                limit: pageSize,
                snapshot: requestSnapshot,
                includeTotal: reset
            )
            if reset {
                items = response.items
                ResponseCache.shared.set(response, for: CacheKey.history)
            } else {
                items.append(contentsOf: response.items)
            }
            if response.totalExact != false {
                totalItems = response.total
            }
            hasMore = response.hasMore ?? false
            nextOffset = requestOffset + response.items.count
            if reset || snapshot == nil {
                snapshot = response.snapshot
            }
        } catch let err {
            if items.isEmpty {
                self.error = ErrorState(err)
            }
        }
        isLoading = false
    }
}
