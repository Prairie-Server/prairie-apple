import SwiftUI

/// List of recently watched items from the user's history.
struct HistoryView: View {
    @State private var items: [BrowseItem] = []
    @State private var isLoading = false
    @State private var error: ErrorState?
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize

    private var columns: [GridItem] {
        AdaptiveColumns.posters(for: hSize)
    }

    var body: some View {
        Group {
            if !items.isEmpty {
                gridContent
            } else if let error {
                ErrorView(state: error, onRetry: { Task { await loadHistory() } })
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
            await loadHistory()
        }
        .refreshable {
            await loadHistory()
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    MediaCard(
                        title: item.title,
                        posterUrl: item.posterUrl ?? "",
                        thumbhash: item.posterThumbhash,
                        year: item.year,
                        userState: item.userState,
                        overlayData: OverlayData.from(item),
                        action: {
                            router.navigate(to: .itemDetail(contentId: item.contentId))
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(ContinuumTheme.padding)
        }
    }

    private func loadHistory() async {
        if items.isEmpty,
           let cached: CatalogResponse = ResponseCache.shared.get(CacheKey.history) {
            items = cached.items
        }
        if items.isEmpty {
            isLoading = true
        }
        error = nil
        do {
            let response: CatalogResponse = try await ContinuumAPI.shared.get(
                "/api/v1/history"
            )
            ResponseCache.shared.set(response, for: CacheKey.history)
            items = response.items
        } catch let err {
            if items.isEmpty {
                self.error = ErrorState(err)
            }
        }
        isLoading = false
    }
}
