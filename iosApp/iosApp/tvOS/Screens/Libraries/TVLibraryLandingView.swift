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
    /// Active focus hand-down token from the shell (incremented when the
    /// Libraries root is selected).
    var focusRequest: Int = 0
    /// Whether the top menu currently holds focus. The mode slider selects a
    /// mode on focus, so kicks issued while the user is still in the menu
    /// would yank focus down into the content mid-slide.
    var isTopMenuFocused: Bool = false
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
    @Environment(AudioPlaybackStore.self) private var audioStore
    @Namespace private var collectionsFocusNamespace

    /// Re-seed counter bumped on mode switch and first data arrival. Added to
    /// `focusRequest` so the combined token changes (and the primary content
    /// element re-claims focus) at those moments too — not just on root entry.
    @State private var focusKickNonce = 0

    /// Combined token handed to whichever element is the primary focus target
    /// for the current mode/state.
    private var landingFocusRequest: Int { focusRequest + focusKickNonce }

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
        // Re-seed focus when the mode is toggled and when content first
        // arrives (rows/cards mount after the async load, so the initial token
        // would otherwise land before there is anything to focus). Each kick
        // is gated on the top menu NOT holding focus: the mode slider selects
        // a mode on focus alone, so an ungated kick would pull focus out of
        // the menu while the user d-pads across Recommended/Collections,
        // making the slider unusable. When the hand-off from the menu is
        // active (root selection), menu focus is already suppressed and
        // relinquished, so the kicks still fire.
        .onChange(of: selectedMode) { _, _ in
            if !isTopMenuFocused { focusKickNonce += 1 }
        }
        .onChange(of: sections.isEmpty) { _, isEmpty in
            if !isEmpty, !isTopMenuFocused { focusKickNonce += 1 }
        }
        .onChange(of: collectionSections.isEmpty) { _, isEmpty in
            if !isEmpty, !isTopMenuFocused { focusKickNonce += 1 }
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
                onPlayTap: { item in
                    if item.isAudiobook {
                        audioStore.play(contentId: item.contentId)
                        return
                    }
                    router.navigate(
                        to: .player(
                            contentId: item.contentId,
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
                focusRequest: landingFocusRequest,
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
                // Match Home exactly: the first content row always makes its
                // first item the default focus, so d-pad Down from the hero
                // lands on item #1 (e.g. the first Continue Watching card)
                // instead of whichever card sits geometrically under the hero.
                // This is safe alongside the hero's own default-focus because
                // the hero deterministically wins INITIAL focus via its
                // focusRequest kick (set in heroSection) — the row flag only
                // governs d-pad entry, never the initial claim. When there is
                // no hero, the first row also takes the imperative entry kick
                // and the Up-to-menu hand-off.
                let isFirstRow = index == 0
                let isPrimaryWithoutHero = featuredSection == nil && isFirstRow
                SectionRow(
                    section: section,
                    onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                    prefersDefaultFocusOnFirstItem: isFirstRow,
                    focusRequest: isPrimaryWithoutHero ? landingFocusRequest : 0,
                    onMoveUp: isPrimaryWithoutHero ? onTopMenuFocusRequest : nil
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
                                    focusRequest: isFirstOverall ? landingFocusRequest : 0,
                                    onMoveUp: isFirstOverall ? onTopMenuFocusRequest : nil,
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

// MARK: - Collection card

/// Attaches an Up-move handler only when one is supplied, so that cards which
/// should NOT hand focus up (every card except the first) don't intercept and
/// consume the Up command the focus engine needs to move between grid rows.
private struct TVCollectionCardMoveUpHandler: ViewModifier {
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

/// Vertical poster card for a collection. Matches the dimensions and
/// caption grammar of `TVMediaCard` so a collections grid reads as the
/// same visual family as the library's movie/show grid — just with
/// "items" replacing "year" under the title.
private struct TVCollectionCard: View {
    let collection: LibraryCollection
    var prefersDefaultFocus: Bool = false
    var defaultFocusNamespace: Namespace.ID? = nil
    /// Programmatic focus kick: when this becomes non-zero (the Collections
    /// layout was swapped in / the Libraries root was selected) focus jumps
    /// to this card, since `prefersDefaultFocus` alone doesn't fire when the
    /// scope isn't being entered by the engine.
    var focusRequest: Int = 0
    /// Supplied only to the first collection card: Up returns focus to the top
    /// menu — the Collections analogue of the Recommended layout's first-row
    /// hand-up. Attached to this card alone so Up from lower grid rows still
    /// moves to the row above instead of jumping to the menu.
    var onMoveUp: (() -> Void)? = nil
    let action: () -> Void

    @FocusState private var isFocused: Bool
    /// Last hand-down token applied, so each token claims focus exactly once.
    /// The card lives in a `LazyVGrid`; without the guard, `onAppear` re-fires
    /// when the first card is recycled back into view on scroll-up and would
    /// yank focus away from the row the user was navigating.
    @State private var lastAppliedFocusRequest = 0

    private let cardWidth: CGFloat = 220
    private var cardHeight: CGFloat { cardWidth * 1.5 } // 2:3 poster ratio

    var body: some View {
        VStack(spacing: 16) {
            collectionButton

            caption
        }
        .frame(width: cardWidth)
        .onAppear { applyFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in applyFocusRequest(request) }
        .modifier(TVCollectionCardMoveUpHandler(onMoveUp: onMoveUp))
    }

    private func applyFocusRequest(_ request: Int) {
        guard request > 0, request != lastAppliedFocusRequest else { return }
        lastAppliedFocusRequest = request
        isFocused = true
    }

    private var collectionButton: some View {
        Button(action: action) {
            posterImage
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .applyDefaultFocusIfNeeded(prefersDefaultFocus, namespace: defaultFocusNamespace)
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
