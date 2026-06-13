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
    /// Token handed to the primary row so its first card claims focus.
    @State private var contentFocusToken = 0

    @Environment(AppRouter.self) private var router

    // MARK: - Derived

    private var contentSections: [ResolvedSection] {
        sections.filter { !$0.isFeatured && !$0.items.isEmpty }
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

            // Floats over the reserved band; never focusable or hit-testable.
            TVFocusMarquee(content: marqueeModel.content, scale: .library)
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

    /// Rows-only scroll under the fixed marquee and pill row. The enclosing
    /// VStack places this scroll view in a frame that starts at the §5.7
    /// row slot, so row 1 rests just below the marquee and the focus engine
    /// can't pull it higher.
    private var rowsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 30, pinnedViews: []) {
                if isLoadingSections && sections.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let error = sectionsError, sections.isEmpty {
                    ErrorView(state: error, onRetry: { Task { await loadContent() } })
                } else if !hasFocusableContent {
                    emptyHint
                } else {
                    rows
                }
            }
            .padding(.bottom, ContinuumTheme.largePadding)
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(Array(contentSections.enumerated()), id: \.element.id) { index, section in
            // Row 1 is always an items row (§6.2) so entry focus gives the
            // marquee something rich to preview; it takes the imperative
            // entry kick and the boundary hand-up to the pill row.
            SectionRow(
                section: section,
                onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                prefersDefaultFocusOnFirstItem: index == 0,
                focusRequest: index == 0 ? contentFocusToken : 0,
                onMoveUp: index == 0 ? onMoveUp : nil,
                onItemFocus: { item in
                    marqueeModel.preview(TVMarqueeContent(item: item, rowTitle: section.title))
                },
                cardWidth: ContinuumTheme.Skyline.densePosterCardWidth
            )

            if index == 0 {
                collectionsRow(isPrimary: false)
            }
        }

        // No item rows at all → the collections row leads and takes the
        // entry focus claim instead.
        if contentSections.isEmpty {
            collectionsRow(isPrimary: true)
        }
    }

    @ViewBuilder
    private func collectionsRow(isPrimary: Bool) -> some View {
        if !rowCollections.isEmpty {
            TVLibraryCollectionsRow(
                collections: rowCollections,
                focusRequest: isPrimary ? contentFocusToken : 0,
                onMoveUp: isPrimary ? onMoveUp : nil,
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
/// collections by item count, a trailing `See All` card that jumps to the
/// Collections pill, and marquee previews on focus. Fan cards arrive in
/// Phase 4 — these reuse the dense poster geometry of row 1.
private struct TVLibraryCollectionsRow: View {
    let collections: [LibraryCollection]
    /// Programmatic focus kick for the rare collections-only library —
    /// mirrors `MediaRow.focusRequest`.
    var focusRequest: Int = 0
    /// Boundary hand-up, supplied only when this row is the primary row.
    var onMoveUp: (() -> Void)? = nil
    let onOpen: (LibraryCollection) -> Void
    let onSeeAll: (() -> Void)?
    let onItemFocus: ((LibraryCollection) -> Void)?

    @FocusState private var focusedCardId: String?

    private let seeAllCardId = "see-all"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Collections")
                .font(.continuumHeadline)
                .foregroundColor(.continuumOnSurface)
                .padding(.horizontal, ContinuumTheme.safePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(collections) { collection in
                        TVCollectionsRowCard(collection: collection) {
                            onOpen(collection)
                        }
                        .focused($focusedCardId, equals: collection.id)
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
        .modifier(TVCollectionsRowMoveUpHandler(onMoveUp: onMoveUp))
        .onChange(of: focusRequest) { _, request in
            guard request > 0, let firstId = collections.first?.id else { return }
            focusedCardId = firstId
        }
        .onChange(of: focusedCardId) { _, newValue in
            guard let newValue,
                  let collection = collections.first(where: { $0.id == newValue }) else { return }
            onItemFocus?(collection)
        }
    }

    private var seeAllCard: some View {
        let width = ContinuumTheme.Skyline.densePosterCardWidth
        let height = width * 1.5

        return VStack(alignment: .leading, spacing: 16) {
            Button {
                onSeeAll?()
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(.continuumOnSurface.opacity(0.85))

                    Text("See All")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.continuumOnSurface)
                }
                .frame(width: width, height: height)
                .background(Color.continuumSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
            }
            .buttonStyle(.card)
            .focused($focusedCardId, equals: seeAllCardId)
            .accessibilityLabel("See all collections")

            // Caption spacer keeps the card top-aligned with its siblings.
            Text(" ")
                .font(.continuumSubheadline)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(width: width)
    }
}

/// Attaches an Up-move handler only when one is supplied so a row that
/// shouldn't hand focus up (anything but the primary row) never consumes
/// the Up command the focus engine needs for row-to-row movement.
private struct TVCollectionsRowMoveUpHandler: ViewModifier {
    let onMoveUp: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onMoveUp {
            content.onMoveCommand { direction in
                if direction == .up {
                    onMoveUp()
                }
            }
        } else {
            content
        }
    }
}

/// Dense poster-geometry collection card for the inline row. Matches the
/// caption grammar of `MediaCard` so the shelf reads as the same family
/// as row 1.
private struct TVCollectionsRowCard: View {
    let collection: LibraryCollection
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private let cardWidth = ContinuumTheme.Skyline.densePosterCardWidth
    private var cardHeight: CGFloat { cardWidth * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: action) {
                artwork
            }
            .buttonStyle(.card)
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.continuumSubheadline)
                    .foregroundColor(isFocused ? .continuumOnSurface : .continuumOnSurface.opacity(0.85))
                    .lineLimit(2, reservesSpace: true)
                    .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)

                if let count = collection.itemCount, count > 0 {
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .frame(width: cardWidth)
    }

    private var artwork: some View {
        Group {
            if let posterUrl = collection.posterUrl, !posterUrl.isEmpty {
                AsyncImageView(
                    url: posterUrl,
                    thumbhash: collection.posterThumbhash,
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
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
    }

    private var hue: Double {
        var hasher = Hasher()
        hasher.combine(collection.id)
        let raw = UInt(bitPattern: hasher.finalize())
        return Double(raw % 360) / 360.0
    }
}
#endif
