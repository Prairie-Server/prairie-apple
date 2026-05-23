import SwiftUI

/// Full-screen search with debounced query and grid results — Plezy style.
struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @Environment(AppRouter.self) private var router
    private let usesTVTopMenuInset: Bool

    init(usesTVTopMenuInset: Bool = true) {
        self.usesTVTopMenuInset = usesTVTopMenuInset
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ContinuumTheme.padding) {
                if shouldShowFilters {
                    mediaTypePicker
                        .padding(.horizontal, ContinuumTheme.padding)
                }

                content
            }
            .padding(.horizontal, ContinuumTheme.padding)
            #if os(tvOS)
            .padding(.top, usesTVTopMenuInset ? TVTopMenuLayout.contentTopInset : ContinuumTheme.padding)
            #else
            .padding(.top, ContinuumTheme.smallPadding)
            #endif
#if os(tvOS)
            .continuumFormWidth(tvSearchContentWidth)
#endif
        }
        .continuumBackground()
        #if os(tvOS)
        .safeAreaPadding(.horizontal, tvSearchSafeHorizontalPadding)
        #endif
        .navigationTitle("Search")
        .continuumNavigationTitleDisplayMode(.inline)
        .continuumToolbarColorSchemeDark()
        .continuumNavigationBarSurfaceBackground()
        .continuumSearchable(text: $viewModel.query, prompt: "Search movies, series...")
        .onChange(of: viewModel.query) { _, _ in
            viewModel.onQueryChanged()
        }
        .onChange(of: viewModel.selectedMediaType) { _, _ in
            Task { await viewModel.applyMediaType() }
        }
    }

    // MARK: - Shared Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching && viewModel.results.isEmpty {
            Color.clear
        } else if let error = viewModel.error {
            ErrorView(state: error, onRetry: { Task { await viewModel.performSearch() } })
        } else if viewModel.hasSearched && viewModel.results.isEmpty {
            VStack {
                Spacer(minLength: 80)
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try a different search term"
                )
            }
        } else if viewModel.results.isEmpty {
            VStack {
                Spacer(minLength: 80)
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Search Silo",
                    subtitle: "Find movies and series"
                )
            }
        } else {
            VStack(alignment: .leading, spacing: ContinuumTheme.padding) {
                Text("\(viewModel.total) result\(viewModel.total == 1 ? "" : "s")")
                    .font(.continuumCaption)
                    .foregroundColor(.continuumSecondaryText)

#if os(tvOS)
                TVCatalogGrid(
                    items: viewModel.results,
                    isLoading: viewModel.isSearching,
                    hasMore: viewModel.hasMore,
                    onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                    onNearEnd: { _ in
                        Task { await viewModel.loadMore() }
                    },
                    columnCount: 6,
                    cardWidth: 220,
                    prefersDefaultFocusOnFirstItem: true
                )
#else
                CatalogGrid(
                    items: viewModel.results,
                    isLoading: viewModel.isSearching,
                    hasMore: viewModel.hasMore,
                    onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                    onLoadMore: {
                        Task { await viewModel.loadMore() }
                    }
                )
#endif
            }
        }
    }

    private var shouldShowFilters: Bool {
        !viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var mediaTypePicker: some View {
        Picker("Media Type", selection: $viewModel.selectedMediaType) {
            ForEach(SearchMediaType.allCases) { mediaType in
                Text(mediaType.title)
                    .tag(mediaType)
            }
        }
        .pickerStyle(.segmented)
#if os(tvOS)
        .continuumFormWidth(tvFilterWidth)
#endif
    }

#if os(tvOS)
    /// Search needs a balanced horizontal inset so the page body clears the
    /// collapsed sidebar without shifting the whole screen right.
    private var tvSearchSafeHorizontalPadding: CGFloat { 110 }

    /// Search needs a centered column so the segmented media-type pill and
    /// the poster grid stay visually aligned while still clearing the
    /// collapsed sidebar affordance.
    private var tvSearchContentWidth: CGFloat { 1600 }

    /// Narrower than the results column so the segmented control reads as a
    /// centered pill rather than stretching across the whole search page.
    private var tvFilterWidth: CGFloat { 760 }
#endif
}
