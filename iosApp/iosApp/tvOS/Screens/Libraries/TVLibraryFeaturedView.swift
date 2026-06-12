#if os(tvOS)
import SwiftUI

/// `Featured` pill content of a library tab: hero carousel + the server's
/// recommended section rows, tuned for discovery (Skyline §6.2). This is
/// the landing default for every library type.
struct TVLibraryFeaturedView: View {
    let library: Library
    /// Focus hand-down token from the shell — claims the hero (or the
    /// first row when there is no hero) on tab entry.
    var focusRequest: Int = 0
    /// Whether the top menu currently holds focus. Deferred focus claims
    /// (content arriving after the entry token) are dropped while the user
    /// is still up in the menu so data loads never yank focus.
    var isTopMenuFocused: Bool = false
    /// Boundary hand-up — fires when Up can't reach the pill row
    /// geometrically (e.g. content still loading).
    let onMoveUp: (() -> Void)?

    // MARK: - State

    @State private var sections: [ResolvedSection] = []
    @State private var isLoadingSections = true
    @State private var sectionsError: ErrorState? = nil
    @State private var heroTintColor: Color = .continuumBackground
    @State private var heroBackdropURL: String?
    @State private var heroBackdropThumbhash: String?

    /// Entry tokens that arrived before any focusable content existed.
    /// Rows and the hero mount after the async section load, so the
    /// initial hand-down would otherwise land on nothing.
    @State private var hasPendingFocusClaim = false
    @State private var lastShellFocusRequest = 0
    /// Token handed to whichever element is the primary focus target.
    @State private var contentFocusToken = 0

    @Environment(AppRouter.self) private var router
    @Environment(AudioPlaybackStore.self) private var audioStore

    // MARK: - Derived

    private var featuredSection: ResolvedSection? {
        sections.first(where: { $0.isFeatured && !$0.items.isEmpty })
    }

    private var contentSections: [ResolvedSection] {
        sections.filter { !$0.isFeatured && !$0.items.isEmpty }
    }

    private var hasFocusableContent: Bool {
        featuredSection != nil || !contentSections.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            TVRootHeroBackdrop(
                tintColor: heroTintColor,
                artworkURL: heroBackdropURL,
                artworkThumbhash: heroBackdropThumbhash,
                isVisible: featuredSection != nil
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: contentSpacing, pinnedViews: []) {
                    heroSection
                    contentRows
                }
                .padding(.bottom, ContinuumTheme.largePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadSections()
        }
        .onAppear { noteShellFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in noteShellFocusRequest(request) }
        .onChange(of: sections.isEmpty) { _, isEmpty in
            if !isEmpty, hasPendingFocusClaim {
                claimContentFocusIfReady()
            }
        }
    }

    // MARK: - Layout

    // The hero's backdrop ignores the top safe area; putting it first in the
    // scroll lets it bleed to the very top of the screen under the global app
    // header and the pill row.
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
                extraTopInset: ContinuumTheme.Skyline.libraryHeroExtraTopInset,
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
                focusRequest: contentFocusToken,
                onMoveUp: onMoveUp
            )
        } else {
            Color.clear
                .frame(height: ContinuumTheme.Skyline.libraryContentTopInset)
        }
    }

    @ViewBuilder
    private var contentRows: some View {
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
                // focusRequest kick — the row flag only governs d-pad entry,
                // never the initial claim. When there is no hero, the first
                // row also takes the imperative entry kick and the boundary
                // hand-up.
                let isFirstRow = index == 0
                let isPrimaryWithoutHero = featuredSection == nil && isFirstRow
                SectionRow(
                    section: section,
                    onItemTap: { router.navigate(to: .itemDetail(contentId: $0)) },
                    prefersDefaultFocusOnFirstItem: isFirstRow,
                    focusRequest: isPrimaryWithoutHero ? contentFocusToken : 0,
                    onMoveUp: isPrimaryWithoutHero ? onMoveUp : nil
                )
            }
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

    /// When the server has no featured section, the pill row becomes the
    /// chrome directly above the first row. Use a tighter follow-on gap so
    /// the first row doesn't read like a missing hero slot.
    private var contentSpacing: CGFloat {
        featuredSection == nil ? 20 : 44
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
}
#endif
