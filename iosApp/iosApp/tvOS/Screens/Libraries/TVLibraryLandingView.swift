#if os(tvOS)
import SwiftUI

enum TVLibraryLandingMode: String, CaseIterable, Identifiable {
    case recommended
    case collections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return "Recommended"
        case .collections: return "Collections"
        }
    }

    var systemImage: String {
        switch self {
        case .recommended: return "sparkles"
        case .collections: return "square.stack.fill"
        }
    }

    var alternate: TVLibraryLandingMode {
        switch self {
        case .recommended: return .collections
        case .collections: return .recommended
        }
    }
}

/// Lean-back library landing for tvOS.
///
/// - **Recommended** — hero carousel + server-provided recommended
///   section rows. This is the default landing, tuned for discovery.
/// - **Collections** — a vertical grid of every collection in this
///   library. Taps navigate to each collection's detail page.
///
/// The app-level `TVTopMenuBar` owns root navigation and library-mode controls,
/// so this view avoids its old local tab chrome.
struct TVLibraryLandingView: View {
    let library: Library
    @Binding var selectedMode: TVLibraryLandingMode
    let onTopMenuFocusRequest: (() -> Void)?

    // MARK: - State

    @State private var sections: [ResolvedSection] = []
    @State private var filters: CatalogFilters? = nil
    @State private var collectionSections: [LibraryCollectionSection] = []
    @State private var isLoadingSections = true
    @State private var isLoadingFilters = true
    @State private var isLoadingCollections = false
    @State private var sectionsError: ErrorState? = nil
    @State private var heroTintColor: Color = .continuumBackground
    @State private var heroBackdropURL: String?
    @State private var heroBackdropThumbhash: String?

    @Environment(AppRouter.self) private var router
    @Namespace private var collectionsFocusNamespace

    // MARK: - Derived

    private var featuredSection: ResolvedSection? {
        sections.first(where: { $0.isFeatured && !$0.items.isEmpty })
    }

    private var contentSections: [ResolvedSection] {
        sections.filter { !$0.isFeatured && !$0.items.isEmpty }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            TVRootHeroBackdrop(
                tintColor: heroTintColor,
                artworkURL: heroBackdropURL,
                artworkThumbhash: heroBackdropThumbhash,
                isVisible: selectedMode == .recommended && featuredSection != nil
            )

            Group {
                switch selectedMode {
                case .recommended:
                    recommendedLayout
                case .collections:
                    collectionsLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            async let sectionsTask: Void = loadSections()
            async let filtersTask: Void = loadFilters()
            _ = await (sectionsTask, filtersTask)
        }
        .task(id: selectedMode) {
            guard selectedMode == .collections else { return }
            guard collectionSections.isEmpty, !isLoadingCollections else { return }
            await loadCollections()
        }
    }

    // MARK: - Per-tab layouts

    private var recommendedLayout: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: recommendedContentSpacing, pinnedViews: []) {
                recommendedTab
            }
            .padding(.bottom, ContinuumTheme.largePadding)
        }
    }

    private var collectionsLayout: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 44, pinnedViews: []) {
                collectionsTab
            }
            .padding(.bottom, ContinuumTheme.largePadding)
        }
    }

    // MARK: - Recommended tab

    @ViewBuilder
    private var recommendedTab: some View {
        heroSection
        recommendedSections
    }

    // The hero's backdrop ignores the top safe area; putting it first in the
    // scroll lets it bleed to the very top of the screen under the global app
    // header.
    @ViewBuilder
    private var heroSection: some View {
        if let featured = featuredSection {
            FeaturedCarousel(
                items: featured.items,
                onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                onPlayTap: {
                    router.navigate(
                        to: .player(
                            contentId: $0,
                            startFromBeginning: false,
                            resumePosition: nil
                        )
                    )
                },
                prefersDefaultFocus: true,
                onBackdropTintChange: { heroTintColor = $0 },
                onBackdropArtworkChange: { url, thumbhash in
                    withAnimation(.easeInOut(duration: 0.65)) {
                        heroBackdropURL = url
                        heroBackdropThumbhash = thumbhash
                    }
                },
                rendersAmbientBackdrop: false,
                prefersTightTVOSLayout: true,
                onMoveUp: onTopMenuFocusRequest
            )
        } else {
            Color.clear
                .frame(height: pageTopInset)
        }
    }

    @ViewBuilder
    private var recommendedSections: some View {
        if isLoadingSections && sections.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 300)
        } else if let error = sectionsError, sections.isEmpty {
            ErrorView(state: error, onRetry: { Task { await loadSections() } })
        } else if contentSections.isEmpty && featuredSection == nil {
            emptyHint
        } else {
            ForEach(Array(contentSections.enumerated()), id: \.element.id) { index, section in
                SectionRow(
                    section: section,
                    onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                    prefersDefaultFocusOnFirstItem: index == 0,
                    onMoveUp: featuredSection == nil && index == 0 ? onTopMenuFocusRequest : nil
                )
            }
        }
    }

    // MARK: - Collections tab

    @ViewBuilder
    private var collectionsTab: some View {
        Color.clear
            .frame(height: pageTopInset)

        if isLoadingCollections && collectionSections.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 300)
        } else if collectionSections.isEmpty {
            EmptyStateView(
                icon: "square.stack",
                title: "No collections yet",
                subtitle: "Collections created on the server will appear here."
            )
            .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            // Only the very first card of the first NON-EMPTY section
            // claims default focus when the tab appears. Skipping empty
            // sections matters: grouped responses can include groups with
            // no collections, and falling back to `collectionSections.first`
            // would leave the Collections tab without an initial focus
            // target on tvOS.
            let focusTarget = collectionSections
                .first(where: { !$0.collections.isEmpty })
            let firstSectionId = focusTarget?.id
            let firstCardId = focusTarget?.collections.first?.id

            VStack(alignment: .leading, spacing: 44) {
                ForEach(collectionSections) { section in
                    VStack(alignment: .leading, spacing: 20) {
                        if !section.name.isEmpty {
                            Text(section.name)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.continuumOnSurface)
                                .padding(.leading, ContinuumTheme.safePadding)
                        }
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 40),
                                count: 6
                            ),
                            alignment: .leading,
                            spacing: 60
                        ) {
                            ForEach(section.collections) { collection in
                                let isFirstOverall =
                                    section.id == firstSectionId && collection.id == firstCardId
                                TVCollectionCard(
                                    collection: collection,
                                    prefersDefaultFocus: isFirstOverall,
                                    defaultFocusNamespace: collectionsFocusNamespace,
                                    action: {
                                        router.navigate(to: .libraryCollection(
                                            libraryId: library.id,
                                            collectionId: collection.id,
                                            title: collection.name,
                                            kind: collection.kind
                                        ))
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, ContinuumTheme.safePadding)
                    }
                }
            }
            .focusScope(collectionsFocusNamespace)
            .focusSection()
            .padding(.top, 12)
        }
    }

    // MARK: - Empty state (Recommended tab)

    private var emptyHint: some View {
        EmptyStateView(
            icon: library.type == "series" ? "tv" : "film.stack",
            title: "\(library.name) is empty",
            subtitle: "Add media to this library on the server to see it here."
        )
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    // MARK: - Constants

    /// Top padding applied when this library page has no hero above it.
    /// Clears the custom app-level top menu.
    private var pageTopInset: CGFloat { TVTopMenuLayout.contentTopInset }

    /// When the server has no featured section, the top bar becomes the
    /// first element in the scroll. Use a tighter follow-on gap so the
    /// first row doesn't read like a missing hero slot.
    private var recommendedContentSpacing: CGFloat {
        featuredSection == nil ? 20 : 44
    }

    // MARK: - Data

    private func loadSections() async {
        isLoadingSections = true
        sectionsError = nil
        do {
            let response = try await ContinuumAPI.shared.librarySections(libraryId: library.id)
            sections = response.sections
        } catch {
            sectionsError = ErrorState(error)
        }
        isLoadingSections = false
    }

    private func loadFilters() async {
        isLoadingFilters = true
        do {
            filters = try await ContinuumAPI.shared.catalogFilters(libraryId: library.id)
        } catch {
            filters = nil
        }
        isLoadingFilters = false
    }

    private func loadCollections() async {
        isLoadingCollections = true
        do {
            let response = try await ContinuumAPI.shared.libraryCollections(libraryId: library.id)
            collectionSections = response.resolvedSections
        } catch {
            collectionSections = []
        }
        isLoadingCollections = false
    }
}

// MARK: - Library shortcut controls

private struct LandingShortcutButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .buttonStyle(LandingShortcutButtonStyle(isSelected: isSelected))
    }
}

private struct LandingShortcutButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        LandingShortcutButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct LandingShortcutButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            }
            .shadow(color: isFocused ? .white.opacity(0.08) : .clear, radius: 10)
            .scaleEffect(scale)
            .focusEffectDisabled()
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isSelected)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        if isFocused { return .white }
        if isSelected { return .white }
        return Color.continuumOnSurface.opacity(0.80)
    }

    private var backgroundColor: Color {
        if isFocused { return Color.white.opacity(0.12) }
        if isSelected { return Color.white.opacity(0.12) }
        return Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        if isFocused { return Color.white.opacity(0.28) }
        if isSelected { return Color.white.opacity(0.20) }
        return Color.white.opacity(0.06)
    }

    private var scale: CGFloat {
        let base: CGFloat = isFocused ? 1.025 : 1.0
        return configuration.isPressed ? base * 0.98 : base
    }
}

// MARK: - Library browse view (inline Plex-style grid)

/// Plex-style inline library browser. Renders a filter bar with a
/// genre dropdown, a sort dropdown, and a live item count, followed by
/// a 6-column poster grid. Owns its own `TVLibraryGridViewModel` so
/// pagination + prefetch work exactly as they do in the full-screen
/// grid view; changing a filter calls `applyFilter` and the grid
/// repaginates in place.
private struct TVLibraryBrowseView<Header: View>: View {
    let library: Library
    let filters: CatalogFilters?
    let onItemTap: (String) -> Void
    let header: () -> Header

    @State private var viewModel: TVLibraryGridViewModel
    @State private var selectedGenre: String? = nil
    // Default sort mirrors the grid VM's `TVLibraryFilter.none.sort`
    // (title). Changing this without also changing the VM default
    // would cause the dropdown label to lie about what the server
    // actually returned on first load.
    @State private var selectedSort: String = "title"
    @State private var selectedPrefix: String? = nil
    @State private var showGenrePicker = false
    @State private var showSortPicker = false

    @Environment(AppRouter.self) private var router

    init(
        library: Library,
        filters: CatalogFilters?,
        onItemTap: @escaping (String) -> Void,
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.library = library
        self.filters = filters
        self.onItemTap = onItemTap
        self.header = header
        _viewModel = State(initialValue: TVLibraryGridViewModel(
            libraryId: library.id,
            libraryType: library.type
        ))
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
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            }
        }
        .fullScreenCover(isPresented: $showGenrePicker) {
            TVFilterPicker(
                title: "Genre",
                options: genreOptions,
                selectedId: selectedGenre ?? genreAllId,
                onSelect: { id in
                    showGenrePicker = false
                    let genre = (id == genreAllId) ? nil : id
                    Task { await apply(genre: genre) }
                },
                onDismiss: { showGenrePicker = false }
            )
        }
        .fullScreenCover(isPresented: $showSortPicker) {
            TVFilterPicker(
                title: "Sort By",
                options: sortOptions.map { TVFilterOption(id: $0.id, label: $0.label) },
                selectedId: selectedSort,
                onSelect: { id in
                    showSortPicker = false
                    Task { await apply(sort: id) }
                },
                onDismiss: { showSortPicker = false }
            )
        }
    }

    // MARK: - Grid column (scrollable)

    private var gridColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 28) {
                header()
                filterBar
                gridContent
            }
            .padding(.bottom, ContinuumTheme.largePadding)
        }
        // Scroll-geometry-driven pagination. Fast scrolls can skip
        // per-cell `.onAppear` triggers, so we also watch the scroll
        // offset directly: whenever less than ~2000pt of unscrolled
        // content remains below the viewport, kick off the next page.
        // Nuke prefetch for the upcoming posters runs at the same
        // threshold so image requests start flying before the user
        // reaches the cells.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let remaining = geometry.contentSize.height
                - geometry.contentOffset.y
                - geometry.containerSize.height
            return remaining < 2000
        } action: { _, nearBottom in
            guard nearBottom else { return }
            Task { await viewModel.loadMoreIfNeeded() }
            let upcomingStart = max(0, viewModel.items.count - 48)
            viewModel.prefetchPosters(in: upcomingStart..<viewModel.items.count)
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 18) {
            genreButton
            Text("by")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.continuumSecondaryText)
            sortButton

            Spacer(minLength: 20)
        }
        .padding(.horizontal, ContinuumTheme.safePadding)
    }

    private var genreButton: some View {
        Button {
            showGenrePicker = true
        } label: {
            FilterDropdownLabel(text: selectedGenre ?? "All")
        }
        .buttonStyle(LandingShortcutButtonStyle(isSelected: false))
    }

    private var sortButton: some View {
        Button {
            showSortPicker = true
        } label: {
            FilterDropdownLabel(text: currentSortLabel)
        }
        .buttonStyle(LandingShortcutButtonStyle(isSelected: false))
    }

    // MARK: - Grid

    @ViewBuilder
    private var gridContent: some View {
        if viewModel.items.isEmpty && viewModel.isLoading {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 400)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            ErrorView(state: error, onRetry: { Task { await viewModel.loadInitial() } })
        } else if viewModel.items.isEmpty {
            EmptyStateView(
                icon: library.type == "series" ? "tv" : "film.stack",
                title: "No titles match",
                subtitle: "Try a different filter."
            )
            .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            TVCatalogGrid(
                items: viewModel.items,
                isLoading: viewModel.isLoading,
                hasMore: viewModel.hasMore,
                onItemTap: onItemTap,
                onNearEnd: { index in
                    Task { await viewModel.loadMoreIfNeeded() }
                    let end = min(index + 48, viewModel.items.count)
                    viewModel.prefetchPosters(in: index..<end)
                },
                // 6 columns × 220pt cards (2:3 posters → 330pt tall) +
                // 5 × 40pt gaps = 1520pt, which fits comfortably inside
                // the grid column once the alphabet rail carves ~128pt
                // off the right side.
                columnCount: 6,
                cardWidth: 220
            )
            .padding(.horizontal, ContinuumTheme.safePadding)
        }
    }

    // MARK: - Filter handlers

    private func apply(genre: String?) async {
        selectedGenre = genre
        // Clear any letter jump when the user changes genre — a fresh
        // facet should start from the top, not the previous A–Z jump.
        selectedPrefix = nil
        var filter = viewModel.filter
        filter.genre = genre
        filter.namePrefix = nil
        await viewModel.applyFilter(filter)
    }

    private func apply(sort: String) async {
        selectedSort = sort
        selectedPrefix = nil
        var filter = viewModel.filter
        filter.sort = sort
        filter.namePrefix = nil
        await viewModel.applyFilter(filter)
    }

    // MARK: - Derived labels

    private struct SortOption {
        let id: String
        let label: String
    }

    private var sortOptions: [SortOption] {
        [
            SortOption(id: "title", label: "Title"),
            SortOption(id: "added_at", label: "Date Added"),
            SortOption(id: "release_date", label: "Release Date"),
            SortOption(id: "rating_imdb", label: "Rating"),
        ]
    }

    private var currentSortLabel: String {
        sortOptions.first(where: { $0.id == selectedSort })?.label ?? "Title"
    }

    /// Sentinel id used by the "All" row in the genre picker. Chosen so
    /// it can never collide with a real genre string returned by the
    /// server.
    private var genreAllId: String { "__all" }

    private var genreOptions: [TVFilterOption] {
        var options = [TVFilterOption(id: genreAllId, label: "All")]
        if let genres = filters?.genres {
            options.append(contentsOf: genres.map { TVFilterOption(id: $0, label: $0) })
        }
        return options
    }
}

// MARK: - Filter dropdown label

/// Label content for the filter dropdown buttons. Does NOT draw its
/// own capsule or handle focus — `LandingShortcutButtonStyle` (applied by the
/// parent Button) owns padding, background, and focus inversion so the
/// dropdown matches the top-bar library badge exactly.
private struct FilterDropdownLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .opacity(0.6)
        }
    }
}

// MARK: - Filter picker (shared modal)

/// Option payload handed to `TVFilterPicker`.
private struct TVFilterOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// Shared picker modal for the filter-bar dropdowns. Matches the
/// visual grammar of `TVLibraryPicker` (dimmed black backdrop, 40pt
/// semibold title, native focus-invert rows, Menu-button dismiss) so
/// every selector in the landing feels like the same family of
/// controls.
private struct TVFilterPicker: View {
    let title: String
    let options: [TVFilterOption]
    let selectedId: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 140)
                    .padding(.bottom, 36)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(options) { option in
                            TVFilterPickerRow(
                                option: option,
                                isSelected: option.id == selectedId,
                                onTap: { onSelect(option.id) }
                            )
                        }
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()

                Spacer(minLength: 0)

                Text("Press Menu to cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand { onDismiss() }
    }
}

private struct TVFilterPickerRow: View {
    let option: TVFilterOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                Text(option.label)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TVFilterPickerRowStyle())
    }
}

private struct TVFilterPickerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVFilterPickerRowBody(configuration: configuration)
    }
}

private struct TVFilterPickerRowBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(isFocused ? .black : .white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.08))
            )
            .shadow(
                color: isFocused ? .black.opacity(0.45) : .clear,
                radius: isFocused ? 20 : 0,
                y: isFocused ? 10 : 0
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Collection card

/// Vertical poster card for a collection. Matches the dimensions and
/// caption grammar of `TVMediaCard` so a collections grid reads as the
/// same visual family as the library's movie/show grid — just with
/// "items" replacing "year" under the title.
private struct TVCollectionCard: View {
    let collection: LibraryCollection
    var prefersDefaultFocus: Bool = false
    var defaultFocusNamespace: Namespace.ID? = nil
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private let cardWidth: CGFloat = 220
    private var cardHeight: CGFloat { cardWidth * 1.5 } // 2:3 poster ratio

    var body: some View {
        VStack(spacing: 16) {
            collectionButton

            caption
        }
        .frame(width: cardWidth)
    }

    @ViewBuilder
    private var collectionButton: some View {
        if let defaultFocusNamespace {
            Button(action: action) {
                posterImage
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .prefersDefaultFocus(prefersDefaultFocus, in: defaultFocusNamespace)
        } else {
            Button(action: action) {
                posterImage
            }
            .buttonStyle(.card)
            .focused($isFocused)
        }
    }

    private var posterImage: some View {
        Group {
            if let posterUrl = collection.posterUrl, !posterUrl.isEmpty {
                CachedAsyncImage(
                    url: posterUrl,
                    targetSize: CGSize(width: cardWidth, height: cardHeight),
                    contentMode: .fill
                )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.55, brightness: 0.45),
                            Color(hue: hue, saturation: 0.35, brightness: 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
    }

    private var caption: some View {
        VStack(spacing: 4) {
            Text(collection.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isFocused ? .continuumOnSurface : .continuumOnSurface.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)

            if collection.kind == .userCollections {
                Text("User collection")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.continuumSecondaryText)
            } else if let count = collection.itemCount, count > 0 {
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.continuumSecondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: cardWidth, alignment: .center)
    }

    private var hue: Double {
        var hasher = Hasher()
        hasher.combine(collection.id)
        let raw = UInt(bitPattern: hasher.finalize())
        return Double(raw % 360) / 360.0
    }
}
#endif
