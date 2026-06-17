#if os(tvOS)
import SwiftUI

/// Shared Skyline landing layout (§6.1): an ambient backdrop, a focus
/// marquee that passively previews the focused card, and native vertically
/// scrolling section rows. Used by **both** Home and the library Browse tabs
/// so the two stay pixel-identical — the only difference is the sections each
/// feeds in.
///
/// Row movement is owned by tvOS focus + the vertical scroll view. Each row
/// remains a native focus section, so row-to-row movement preserves tvOS'
/// geometric focus behavior instead of forcing the first item.
struct TVSkylineSectionFeed: View {
    /// Section rows to page through, in order (already filtered to
    /// non-empty, non-featured by the caller).
    let sections: [ResolvedSection]
    /// Marquee scale. Both call sites pass `.home` so the pages render
    /// identically; kept as a parameter only for call-site clarity.
    var marqueeScale: TVFocusMarquee.Scale = .home
    /// Focus hand-down token from the shell — claims the first card on entry.
    var focusRequest: Int = 0
    /// Whether the top menu currently holds focus. A late content load must
    /// not steal focus while the user is up in the menu.
    var isTopMenuFocused: Bool = false
    /// Up at the first page hands focus to the top bar.
    let onTopMenuFocusRequest: (() -> Void)?
    /// Home uses Back/Menu as a focus ladder: content -> first row/card ->
    /// top menu. Other Skyline hosts keep the shell's default exit behavior.
    var resetsToFirstItemOnExit: Bool = false
    /// Open a content item (detail).
    let onItemTap: (String) -> Void

    /// Debounced focused-card state driving the marquee + backdrop.
    @State private var marqueeModel = TVFocusMarqueeModel()
    /// Token handed to row 1 so its first card claims focus on shell entry.
    @State private var contentFocusToken = 0
    /// The row currently owning card focus. Bound to the vertical scroll view
    /// so each focused row lands at the top of the clipped lower band.
    @State private var focusedSectionID: String?
    /// The card currently owning focus. Used by Home's Back/Menu focus ladder
    /// to distinguish "already on row 1/card 1" from any other content focus.
    @State private var focusedItemID: String?
    /// Entry tokens that arrived before any row mounted — sections load
    /// async, so the initial hand-down would land on nothing.
    @State private var pendingFocusRequest: Int?
    @State private var lastAppliedRequest = 0

    var body: some View {
        ZStack(alignment: .top) {
            TVRootHeroBackdrop(
                tintColor: marqueeModel.tintColor,
                artworkURL: marqueeModel.backdropURL,
                artworkThumbhash: marqueeModel.backdropThumbhash,
                isVisible: marqueeModel.content != nil,
                crossfadeDuration: ContinuumTheme.Skyline.marqueeCrossfadeDuration
            )

            // Native scrolling lives only in the bottom row band. The viewport
            // clips at its top edge so rows do not paint through the marquee
            // title, description, and metadata while they scroll upward.
            scrollingRows
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
        .modifier(TVSkylineExitHandler(isEnabled: resetsToFirstItemOnExit) {
            handleExitCommand()
        })
    }

    // MARK: - Rows

    /// Native vertical row scrolling, clipped to the lower band so rows always
    /// appear from the same bottom area and disappear before the marquee text.
    @ViewBuilder
    private var scrollingRows: some View {
        GeometryReader { proxy in
            let bandHeight = proxy.size.height * ContinuumTheme.Skyline.rowBandHeightFraction
            let visibleBandHeight = max(0, bandHeight)
            let trailingPreviewPadding = max(
                0,
                visibleBandHeight - ContinuumTheme.Skyline.rowBandBottomInset
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: ContinuumTheme.Skyline.rowBandPreviewSpacing) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        featuredRow(section, isFirstRow: index == 0)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(section.id)
                    }
                }
                .scrollTargetLayout()
                // Allows the final row to top-align like every prior row,
                // with a blank preview area underneath instead of clamping.
                .padding(.bottom, trailingPreviewPadding)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedSectionID, anchor: .top)
            .frame(width: proxy.size.width, height: visibleBandHeight, alignment: .topLeading)
            .clipped()
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
        }
    }

    @ViewBuilder
    private func featuredRow(_ section: ResolvedSection, isFirstRow: Bool) -> some View {
        SectionRow(
            section: section,
            onItemTap: onItemTap,
            prefersDefaultFocusOnFirstItem: false,
            focusRequest: isFirstRow ? contentFocusToken : 0,
            onMoveUp: nil,
            onItemFocus: { item in
                previewFocusedItem(item, in: section)
            },
            cardWidth: ContinuumTheme.Skyline.densePosterCardWidth,
            cardVerticalPadding: ContinuumTheme.Skyline.rowBandCardVerticalPadding,
            onMoveDown: nil
        )
    }

    // MARK: - Focus

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
        contentFocusToken += 1
    }

    private func previewFocusedItem(_ item: SectionItem, in section: ResolvedSection) {
        marqueeModel.preview(TVMarqueeContent(item: item, rowTitle: section.title))
        focusedItemID = item.contentId

        guard focusedSectionID != section.id else { return }
        withAnimation(.easeOut(duration: ContinuumTheme.Skyline.rowBandScrollDuration)) {
            focusedSectionID = section.id
        }
    }

    private func handleExitCommand() {
        guard !isFocusedOnFirstItem else {
            onTopMenuFocusRequest?()
            return
        }
        focusFirstItem()
    }

    private var isFocusedOnFirstItem: Bool {
        guard let firstSection = sections.first,
              let firstItem = firstSection.items.first else { return false }
        return focusedSectionID == firstSection.id && focusedItemID == firstItem.contentId
    }

    private func focusFirstItem() {
        guard let firstSection = sections.first else {
            onTopMenuFocusRequest?()
            return
        }

        withAnimation(.easeOut(duration: ContinuumTheme.Skyline.rowBandScrollDuration)) {
            focusedSectionID = firstSection.id
        }
        contentFocusToken += 1
    }
}

private struct TVSkylineExitHandler: ViewModifier {
    let isEnabled: Bool
    let onExit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onExitCommand(perform: onExit)
        } else {
            content
        }
    }
}

#endif
