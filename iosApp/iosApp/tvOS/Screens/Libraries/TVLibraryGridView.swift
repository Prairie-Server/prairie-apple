#if os(tvOS)
import SwiftUI

/// Grid + letter-rail view for a single library on tvOS.
///
/// Can be entered either from the landing page (with a pre-applied filter,
/// e.g. genre=Action) or directly (`TVLibraryFilter.none`) for a full browse.
/// The letter rail always sits on the right and modifies `namePrefix` on the
/// current filter, so "Action / T" is a valid composite state.
struct TVLibraryGridView: View {
    let libraryId: Int
    let libraryName: String
    let libraryType: String
    let initialFilter: TVLibraryFilter
    let subtitle: String?

    @State private var viewModel: TVLibraryGridViewModel
    @State private var selectedPrefix: String? = nil

    @Environment(AppRouter.self) private var router

    init(
        libraryId: Int,
        libraryName: String,
        libraryType: String,
        initialFilter: TVLibraryFilter = .none,
        subtitle: String? = nil
    ) {
        self.libraryId = libraryId
        self.libraryName = libraryName
        self.libraryType = libraryType
        self.initialFilter = initialFilter
        self.subtitle = subtitle
        _viewModel = State(initialValue: TVLibraryGridViewModel(
            libraryId: libraryId,
            libraryType: libraryType,
            initialFilter: initialFilter
        ))
        _selectedPrefix = State(initialValue: initialFilter.namePrefix)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gridColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()

            TVAlphabetRail(selected: $selectedPrefix) { prefix in
                Task { await viewModel.jumpToPrefix(prefix) }
            }
            .padding(.trailing, 32)
        }
        .continuumBackground()
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            }
        }
    }

    // MARK: - Grid column

    private var gridColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                    .padding(.horizontal, ContinuumTheme.safePadding)
                    .padding(.top, ContinuumTheme.smallPadding)

                if viewModel.items.isEmpty && viewModel.isLoading {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 400)
                } else if let error = viewModel.error, viewModel.items.isEmpty {
                    ErrorView(state: error, onRetry: { Task { await viewModel.loadInitial() } })
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        icon: "film.stack",
                        title: "No titles match",
                        subtitle: "Try a different letter or filter."
                    )
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    TVCatalogGrid(
                        items: viewModel.items,
                        isLoading: viewModel.isLoading,
                        hasMore: viewModel.hasMore,
                        onItemTap: { contentId in
                            router.navigate(to: .itemDetail(contentId: contentId))
                        },
                        onNearEnd: { index in
                            Task { await viewModel.loadMoreIfNeeded() }
                            let end = min(index + 48, viewModel.items.count)
                            viewModel.prefetchPosters(in: index..<end)
                        }
                    )
                    .padding(.horizontal, ContinuumTheme.safePadding)
                }
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(libraryName)
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.continuumOnSurface)

            if let prefix = selectedPrefix {
                Text(prefix == "#" ? "Titles starting with a number or symbol" : "Titles starting with \(prefix)")
                    .font(.continuumHeadline)
                    .foregroundColor(.continuumSecondaryText)
            } else if let subtitle {
                Text(subtitle)
                    .font(.continuumHeadline)
                    .foregroundColor(.continuumSecondaryText)
            } else if let total = totalLabel {
                Text(total)
                    .font(.continuumHeadline)
                    .foregroundColor(.continuumSecondaryText)
            }
        }
    }

    private var totalLabel: String? {
        guard !viewModel.items.isEmpty else { return nil }
        return viewModel.hasMore
            ? "\(viewModel.items.count)+ titles"
            : "\(viewModel.items.count) titles"
    }
}
#endif
