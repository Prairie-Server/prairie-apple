#if os(tvOS)
import SwiftUI

/// Shared Skyline landing layout (§6.1): an ambient backdrop, a focus
/// marquee that passively previews the focused card, and one section row at
/// a time pinned to the bottom band. Used by **both** Home and the library
/// Browse tabs so the two stay pixel-identical — the only difference is the
/// sections each feeds in.
///
/// Paging: there is no scroll view, so the focus engine never moves the row
/// while navigating across cards. Up/Down page the band explicitly and the
/// swap crossfades. Entry focus lands on the first row's first card, which
/// the marquee previews immediately.
struct TVSkylineSectionFeed: View {
    /// Section rows to page through, in order (already filtered to
    /// non-empty, non-featured by the caller).
    let sections: [ResolvedSection]
    /// Marquee scale. Both call sites pass `.home` so the pages render
    /// identically; kept as a parameter only for call-site clarity.
    var marqueeScale: TVFocusMarquee.Scale = .home
    /// Focus hand-down token from the shell — claims the first card on entry
    /// and on every page change.
    var focusRequest: Int = 0
    /// Whether the top menu currently holds focus. A late content load must
    /// not steal focus while the user is up in the menu.
    var isTopMenuFocused: Bool = false
    /// Up at the first page hands focus to the top bar.
    let onTopMenuFocusRequest: (() -> Void)?
    /// Open a content item (detail).
    let onItemTap: (String) -> Void

    /// Debounced focused-card state driving the marquee + backdrop.
    @State private var marqueeModel = TVFocusMarqueeModel()
    /// The section currently shown in the bottom band. The feed pages one at
    /// a time (no scroll view) so the focus engine never scrolls the row.
    @State private var pageIndex = 0
    /// Token handed to the visible row so its first card claims focus on
    /// entry and on every page change.
    @State private var contentFocusToken = 0
    /// Entry tokens that arrived before any row mounted — sections load
    /// async, so the initial hand-down would land on nothing.
    @State private var pendingFocusRequest: Int?
    @State private var lastAppliedRequest = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            TVRootHeroBackdrop(
                tintColor: marqueeModel.tintColor,
                artworkURL: marqueeModel.content?.backdropUrl,
                artworkThumbhash: marqueeModel.content?.backdropThumbhash,
                isVisible: marqueeModel.content != nil,
                crossfadeDuration: ContinuumTheme.Skyline.marqueeCrossfadeDuration
            )

            // One section at a time, pinned to the bottom band. Reaches into
            // the bottom overscan so the focused row sits near the physical
            // edge; it re-insets via rowBandBottomInset.
            pagedBand
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)

            // Floats over the band above the row; never focusable or hit-testable.
            TVFocusMarquee(
                content: marqueeModel.content,
                enrichment: marqueeModel.enrichment,
                scale: marqueeScale
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { requestEntryFocus(focusRequest) }
        .onChange(of: focusRequest) { _, request in requestEntryFocus(request) }
        // Rows mount only after the async section load; a deferred entry
        // token re-fires once they exist.
        .onChange(of: sections.map(\.id)) { _, _ in
            if let pending = pendingFocusRequest { requestEntryFocus(pending) }
        }
    }

    // MARK: - Band

    /// One section at a time, bottom-aligned in the band. No scroll view, so
    /// the focus engine can't move the row when navigating across cards.
    /// Up/Down page the band and the swap crossfades.
    @ViewBuilder
    private var pagedBand: some View {
        ZStack(alignment: .bottom) {
            if sections.indices.contains(pageIndex) {
                let section = sections[pageIndex]
                // Row 1 is an items row so entry focus gives the marquee
                // something rich to preview.
                SectionRow(
                    section: section,
                    onItemTap: onItemTap,
                    prefersDefaultFocusOnFirstItem: true,
                    focusRequest: contentFocusToken,
                    onMoveUp: pageIndex == 0 ? onTopMenuFocusRequest : { pageBand(by: -1) },
                    onItemFocus: { item in
                        marqueeModel.preview(TVMarqueeContent(item: item, rowTitle: section.title))
                    },
                    cardWidth: ContinuumTheme.Skyline.densePosterCardWidth,
                    onMoveDown: { pageBand(by: 1) }
                )
                // Natural height so the row hugs its header and bottom-aligns
                // in the band rather than stretching.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, ContinuumTheme.Skyline.rowBandBottomInset)
                .id(section.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: ContinuumTheme.normalDuration),
            value: pageIndex
        )
    }

    // MARK: - Paging & focus

    /// Page the visible band by ±1. Clamps at the ends; Up past the first
    /// row is handled by the row's onMoveUp (to the top bar). Each page hands
    /// focus to the new row's first card via the focus token.
    private func pageBand(by delta: Int) {
        let target = pageIndex + delta
        guard sections.indices.contains(target) else { return }
        pageIndex = target
        contentFocusToken += 1
    }

    /// Entry focus → the first row's first card. Tokens that arrive before
    /// the rows mount wait as a pending claim. A claim is dropped while the
    /// menu holds focus, so neither a late fetch (library loads async, so its
    /// feed mounts after entry) nor a stale token ever yanks focus away from
    /// the user once they've moved up into the bar. On a normal tab entry the
    /// shell has already relinquished the menu, so the claim proceeds. The
    /// request token is monotonic, so re-entry always lands fresh while
    /// onAppear/onChange can't double-claim the same value.
    private func requestEntryFocus(_ request: Int) {
        guard request > 0 else { return }
        guard !sections.isEmpty else {
            pendingFocusRequest = request
            return
        }
        pendingFocusRequest = nil
        if isTopMenuFocused { return }
        guard request != lastAppliedRequest else { return }
        lastAppliedRequest = request
        pageIndex = 0
        contentFocusToken += 1
    }
}
#endif
