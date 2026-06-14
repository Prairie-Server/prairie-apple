#if os(tvOS)
import SwiftUI

/// Browse landing of a library tab (Skyline §6.2): the library-scale
/// focus marquee over dense item rows, with an inline `Collections` row
/// after row 1. The server's featured hero section is ignored on TV
/// surfaces (§9) — there is no carousel; the marquee passively previews
/// whichever card holds focus.
struct TVLibraryBrowseView: View {
    let library: Library
    /// Focus hand-down token from the shell — claims the first card of
    /// row 1 on tab entry.
    var focusRequest: Int = 0
    /// Whether the top menu currently holds focus. Deferred focus claims
    /// (content arriving after the entry token) are dropped while the user
    /// is still up in the menu so data loads never yank focus.
    var isTopMenuFocused: Bool = false
    /// Boundary hand-up — Up from row 1 reaches the pill row.
    let onMoveUp: (() -> Void)?
    /// Commits the Collections pill — the trailing `See All` card jumps
    /// there through the shell so pill selection state stays in one place.
    var onSelectCollectionsPill: (() -> Void)? = nil

    // MARK: - State

    @State private var sections: [ResolvedSection] = []
    @State private var isLoadingSections = true
    @State private var sectionsError: ErrorState? = nil
    /// Top collections by item count for the inline §6.2 row (≤8, with a
    /// trailing See All card).
    @State private var rowCollections: [LibraryCollection] = []
    /// Debounced focused-card state driving the marquee + backdrop.
    @State private var marqueeModel = TVFocusMarqueeModel()

    /// Entry tokens that arrived before any focusable content existed.
    /// Rows mount after the async section load, so the initial hand-down
    /// would otherwise land on nothing.
    @State private var hasPendingFocusClaim = false
    @State private var lastShellFocusRequest = 0
    /// Token handed to the visible row so its first card claims focus on
    /// entry and on every page change.
    @State private var contentFocusToken = 0
    /// The page currently shown in the bottom band. Browse pages one
    /// section at a time (no scroll view), so the focus engine never
    /// scrolls the row and it stays put while moving across cards.
    @State private var pageIndex = 0

    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived

    private var contentSections: [ResolvedSection] {
        sections.filter { !$0.isFeatured && !$0.items.isEmpty }
    }

    /// One entry per swipeable page: the item rows (§6.2 puts the items
    /// row first) followed by the inline Collections shelf when present.
    private enum BrowsePage {
        case section(ResolvedSection)
        case collections
    }

    private var pages: [BrowsePage] {
        var pages = contentSections.map(BrowsePage.section)
        if !rowCollections.isEmpty {
            // §6.2: Collections follows the first items row; with no item
            // rows it leads.
            let insertAt = pages.isEmpty ? 0 : 1
            pages.insert(.collections, at: insertAt)
        }
        return pages
    }

    private var hasFocusableContent: Bool {
        !contentSections.isEmpty || !rowCollections.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            TVRootHeroBackdrop(
                tintColor: marqueeModel.tintColor,
                artworkURL: marqueeModel.content?.backdropUrl,
                artworkThumbhash: marqueeModel.content?.backdropThumbhash,
                isVisible: marqueeModel.content != nil,
                crossfadeDuration: ContinuumTheme.Skyline.marqueeCrossfadeDuration
            )

            // The rows live in a frame that begins at the §5.7 row slot, so
            // the scroll view and the marquee never share a coordinate
            // space — focusing the first card can't overscroll the row up
            // under the marquee (a top inset/padding doesn't constrain the
            // focus engine's scroll-to-visible; a separate frame does). The
            // top spacer is non-interactive and just shows the backdrop
            // through to the marquee band and the pill row.
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: ContinuumTheme.Skyline.libraryFirstRowTop)
                    .allowsHitTesting(false)

                rowsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Reach into the bottom overscan so the focused row sits near the
            // physical edge; it re-insets via rowBandBottomInset.
            .ignoresSafeArea(edges: .bottom)

            // Floats over the reserved band; never focusable or hit-testable.
            TVFocusMarquee(
                content: marqueeModel.content,
                enrichment: marqueeModel.enrichment,
                scale: .library
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadContent()
        }
        .onAppear { noteShellFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in noteShellFocusRequest(request) }
        .onChange(of: hasFocusableContent) { _, hasContent in
            if hasContent, hasPendingFocusClaim {
                claimContentFocusIfReady()
            }
        }
    }

    // MARK: - Layout

    /// One page at a time, pinned to the bottom band. No scroll view, so
    /// the focus engine never scrolls the row when moving across cards.
    /// Up/Down page sections explicitly and the swap crossfades.
    @ViewBuilder
    private var rowsContent: some View {
        if isLoadingSections && sections.isEmpty {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = sectionsError, sections.isEmpty {
            ErrorView(state: error, onRetry: { Task { await loadContent() } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasFocusableContent {
            emptyHint
        } else {
            pagedRows
        }
    }

    @ViewBuilder
    private var pagedRows: some View {
        let pages = pages
        ZStack(alignment: .bottom) {
            if pages.indices.contains(pageIndex) {
                pageRow(for: pages[pageIndex])
                    // Natural height so the row hugs its header and
                    // bottom-aligns in the band rather than stretching.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, ContinuumTheme.Skyline.rowBandBottomInset)
                    .id(pageKey(pages[pageIndex]))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: ContinuumTheme.normalDuration),
            value: pageIndex
        )
    }

    @ViewBuilder
    private func pageRow(for page: BrowsePage) -> some View {
        switch page {
        case .section(let section):
            // Row 1 is an items row (§6.2) so entry focus gives the
            // marquee something rich to preview.
            SectionRow(
                section: section,
                onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                prefersDefaultFocusOnFirstItem: true,
                focusRequest: contentFocusToken,
                onMoveUp: pageIndex == 0 ? onMoveUp : { pageRows(by: -1) },
                onItemFocus: { item in
                    marqueeModel.preview(TVMarqueeContent(item: item, rowTitle: section.title))
                },
                cardWidth: ContinuumTheme.Skyline.densePosterCardWidth,
                onMoveDown: { pageRows(by: 1) }
            )
        case .collections:
            TVLibraryCollectionsRow(
                collections: rowCollections,
                focusRequest: contentFocusToken,
                onMoveUp: pageIndex == 0 ? onMoveUp : { pageRows(by: -1) },
                onMoveDown: { pageRows(by: 1) },
                onOpen: { collection in
                    router.navigate(to: .libraryCollection(
                        libraryId: library.id,
                        collectionId: collection.id,
                        title: collection.name,
                        kind: collection.kind
                    ))
                },
                onSeeAll: onSelectCollectionsPill,
                onItemFocus: { collection in
                    marqueeModel.preview(TVMarqueeContent(collection: collection, rowTitle: "Collections"))
                }
            )
        }
    }

    private func pageKey(_ page: BrowsePage) -> String {
        switch page {
        case .section(let section): return "section:\(section.id)"
        case .collections: return "collections"
        }
    }

    /// Page the visible row by ±1. Clamps at the ends; Up past the first
    /// page is handled by the row's onMoveUp (to the pill row).
    private func pageRows(by delta: Int) {
        let target = pageIndex + delta
        guard pages.indices.contains(target) else { return }
        pageIndex = target
        contentFocusToken += 1
    }

    private var emptyHint: some View {
        EmptyStateView(
            icon: emptyLibraryIcon,
            title: "\(library.name) is empty",
            subtitle: "Add media to this library on the server to see it here."
        )
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private var emptyLibraryIcon: String {
        if library.isSeriesLibrary { return "tv" }
        if library.isAudiobookLibrary { return "book.closed" }
        return "film.stack"
    }

    // MARK: - Focus hand-down

    private func noteShellFocusRequest(_ request: Int) {
        guard request > 0, request != lastShellFocusRequest else { return }
        lastShellFocusRequest = request
        claimContentFocusIfReady()
    }

    private func claimContentFocusIfReady() {
        guard hasFocusableContent else {
            hasPendingFocusClaim = true
            return
        }
        // Deferred claims (content arrived after the entry token) are
        // dropped once the user has moved up into the menu — a late data
        // load must never steal focus mid-navigation.
        if hasPendingFocusClaim, isTopMenuFocused {
            hasPendingFocusClaim = false
            return
        }
        hasPendingFocusClaim = false
        // Entry always lands on the first page.
        pageIndex = 0
        contentFocusToken += 1
    }

    // MARK: - Data

    private func loadContent() async {
        isLoadingSections = true
        sectionsError = nil
        async let collectionsTask = ContinuumAPI.shared.libraryCollections(libraryId: library.id)

        do {
            let response = try await ContinuumAPI.shared.librarySections(libraryId: library.id)
            sections = response.sections
        } catch {
            sectionsError = ErrorState(error)
        }

        // The inline row is glanceable garnish (§6.2) — the Collections
        // pill remains the full catalog, so a failure here just hides it.
        if let collectionsResponse = try? await collectionsTask {
            let all = collectionsResponse.resolvedSections.flatMap(\.collections)
            rowCollections = Array(
                all
                    .sorted { ($0.itemCount ?? 0) > ($1.itemCount ?? 0) }
                    .prefix(8)
            )
        }

        isLoadingSections = false
    }
}

// MARK: - Inline collections row

/// Horizontal `Collections` shelf on the Browse landing (§6.2): up to 8
/// collections by item count rendered as fan cards (§5.6), a trailing
/// `See All` card that jumps to the Collections pill, and marquee previews
/// on focus.
private struct TVLibraryCollectionsRow: View {
    let collections: [LibraryCollection]
    /// Programmatic focus kick for the rare collections-only library —
    /// mirrors `MediaRow.focusRequest`.
    var focusRequest: Int = 0
    /// Boundary hand-up to the previous page / pill row.
    var onMoveUp: (() -> Void)? = nil
    /// Boundary hand-down to the next page.
    var onMoveDown: (() -> Void)? = nil
    let onOpen: (LibraryCollection) -> Void
    let onSeeAll: (() -> Void)?
    let onItemFocus: ((LibraryCollection) -> Void)?

    @FocusState private var focusedCardId: String?
    /// Applied once per token so a freshly-mounted row (page swap) claims
    /// focus on appear, not only on a `focusRequest` change.
    @State private var lastAppliedFocusRequest = 0

    private let seeAllCardId = "see-all"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Collections")
                .font(.continuumHeadline)
                .foregroundColor(.continuumOnSurface)
                .padding(.horizontal, ContinuumTheme.safePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ContinuumTheme.Skyline.fanGridGap) {
                    ForEach(collections) { collection in
                        TVCollectionFanCard(
                            collection: collection,
                            action: { onOpen(collection) },
                            focusBinding: $focusedCardId,
                            focusContentId: collection.id
                        )
                    }

                    if onSeeAll != nil {
                        seeAllCard
                    }
                }
                .padding(.horizontal, ContinuumTheme.safePadding)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .modifier(TVCollectionsRowMoveHandler(onMoveUp: onMoveUp, onMoveDown: onMoveDown))
        .onAppear { applyFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in applyFocusRequest(request) }
        .onChange(of: focusedCardId) { _, newValue in
            guard let newValue,
                  let collection = collections.first(where: { $0.id == newValue }) else { return }
            onItemFocus?(collection)
        }
    }

    private func applyFocusRequest(_ request: Int) {
        guard request > 0, request != lastAppliedFocusRequest,
              let firstId = collections.first?.id else { return }
        lastAppliedFocusRequest = request
        focusedCardId = firstId
    }

    /// Trailing card that jumps to the Collections pill. Sized to the
    /// fan-card row height (§6.2) so it lines up with its neighbours, and
    /// it borrows the fan card's surface + focus grammar to read as one
    /// family.
    private var seeAllCard: some View {
        let width = ContinuumTheme.Skyline.fanCardWidth
        let height = ContinuumTheme.Skyline.fanCardHeight
        let radius = ContinuumTheme.Skyline.fanCardCornerRadius

        return Button {
            onSeeAll?()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: radius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.continuumFanCardSurfaceTop,
                                Color.continuumFanCardSurfaceBottom,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(ContinuumTheme.Skyline.fanCardSurfaceOpacity)

                VStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(.continuumOnSurface.opacity(0.85))

                    Text("See All")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.continuumOnSurface)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        seeAllFocused ? Color.white : Color.continuumOutline,
                        lineWidth: seeAllFocused ? ContinuumTheme.Skyline.fanCardFocusBorderWidth : 1
                    )
            }
        }
        .buttonStyle(TVFanSeeAllButtonStyle())
        .focused($focusedCardId, equals: seeAllCardId)
        .accessibilityLabel("See all collections")
    }

    private var seeAllFocused: Bool { focusedCardId == seeAllCardId }
}

/// Matches `TVCollectionFanCard`'s focus motion for the trailing See All
/// card (scale 1.05 + drop shadow, no system halo).
private struct TVFanSeeAllButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVFanSeeAllButtonBody(configuration: configuration)
    }
}

private struct TVFanSeeAllButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(scale)
            .shadow(
                color: .black.opacity(isFocused ? 0.5 : 0.0),
                radius: isFocused ? 20 : 0,
                y: isFocused ? 10 : 0
            )
            .focusEffectDisabled()
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }

    private var scale: CGFloat {
        let base: CGFloat = isFocused && !reduceMotion ? 1.05 : 1.0
        return configuration.isPressed ? base * 0.97 : base
    }
}

/// Bridges the collections row's boundary up/down move commands to the
/// host (page change), attaching `onMoveCommand` only when a handler is
/// supplied.
private struct TVCollectionsRowMoveHandler: ViewModifier {
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if onMoveUp != nil || onMoveDown != nil {
            content.onMoveCommand { direction in
                switch direction {
                case .up: onMoveUp?()
                case .down: onMoveDown?()
                default: break
                }
            }
        } else {
            content
        }
    }
}

#endif
