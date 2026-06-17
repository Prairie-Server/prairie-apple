#if os(tvOS)
import SwiftUI

/// Shared Skyline landing layout (§6.1): an ambient backdrop, a focus
/// marquee that passively previews the focused card, and a lower-half row
/// stack that shows the active section plus a clipped preview of the next
/// section. Used by **both** Home and the library Browse tabs so the two stay
/// pixel-identical — the only difference is the sections each feeds in.
///
/// Paging: there is no scroll view, so the focus engine never moves the row
/// while navigating across cards. Up/Down page the focused row explicitly and
/// the next-row preview animates into the focused slot while the outgoing row
/// fades behind the marquee area. Entry focus lands on the first row's first
/// card, which the marquee previews immediately.
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
    /// The section currently featured at the top of the lower-half row stack.
    /// The feed pages one at a time (no scroll view) so the focus engine never
    /// scrolls the row.
    @State private var pageIndex = 0
    /// Token handed to the visible row so its first card claims focus on
    /// entry and on every page change.
    @State private var contentFocusToken = 0
    /// Entry tokens that arrived before any row mounted — sections load
    /// async, so the initial hand-down would land on nothing.
    @State private var pendingFocusRequest: Int?
    @State private var lastAppliedRequest = 0
    /// Direction of the most recent row page request. Drives only the outgoing
    /// row fade direction; focus is still claimed by the newly-mounted row.
    @State private var pageTransitionDelta = 0
    /// The row that is leaving during the current page transition. Keeping this
    /// separate from `pageIndex` lets the outgoing first row stay above the new
    /// row long enough to visibly slide/fade out.
    @State private var outgoingPageIndex: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rowPagingNamespace

    var body: some View {
        ZStack(alignment: .top) {
            TVRootHeroBackdrop(
                tintColor: marqueeModel.tintColor,
                artworkURL: marqueeModel.backdropURL,
                artworkThumbhash: marqueeModel.backdropThumbhash,
                isVisible: marqueeModel.content != nil,
                crossfadeDuration: ContinuumTheme.Skyline.marqueeCrossfadeDuration
            )

            // The lower half is a row stack: one interactive focused row plus
            // a passive peek of the next row below it. It reaches into the
            // bottom overscan and re-insets via rowBandBottomInset.
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
            // Home/library refresh their rows on return (e.g. player dismiss).
            // If the user had paged down to a row that vanished (Continue
            // Watching shrinks, permissions/data change), the stale pageIndex
            // would fall out of range and the band would render nothing,
            // stranding the page blank. Clamp it back into range and re-claim
            // focus so the now-visible row's first card re-primes the marquee.
            pageTransitionDelta = 0
            outgoingPageIndex = nil
            if !sections.isEmpty, pageIndex >= sections.count {
                pageIndex = sections.count - 1
                contentFocusToken += 1
            }
            if let pending = pendingFocusRequest { requestEntryFocus(pending) }
        }
    }

    // MARK: - Band

    /// One interactive section plus a non-focusable next-row preview in the
    /// lower half of the screen. No scroll view, so the focus engine can't
    /// move the row when navigating across cards. Up/Down page the featured
    /// row by animating the existing next-row preview into the focused slot.
    @ViewBuilder
    private var pagedBand: some View {
        GeometryReader { proxy in
            let bandHeight = proxy.size.height * ContinuumTheme.Skyline.rowBandHeightFraction
            let visibleBandHeight = max(0, bandHeight - ContinuumTheme.Skyline.rowBandBottomInset)

            ZStack(alignment: .topLeading) {
                if sections.indices.contains(pageIndex) {
                    let section = sections[pageIndex]
                    VStack(alignment: .leading, spacing: ContinuumTheme.Skyline.rowBandPreviewSpacing) {
                        featuredRow(section)

                        if let previewSection = nextPreviewSection {
                            TVSectionRowPreview(
                                section: previewSection,
                                cardWidth: ContinuumTheme.Skyline.densePosterCardWidth
                            )
                            .modifier(rowPagingGeometry(for: previewSection))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .id(section.id)
                    .zIndex(rowStackZIndex(for: section))
                    .transition(rowStackTransition)
                }
            }
            .frame(width: proxy.size.width, height: visibleBandHeight, alignment: .topLeading)
            .clipped()
            .padding(.bottom, ContinuumTheme.Skyline.rowBandBottomInset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
        }
        .animation(
            rowPageAnimation,
            value: pageIndex
        )
    }

    @ViewBuilder
    private func featuredRow(_ section: ResolvedSection) -> some View {
        // Row 1 is an items row so entry focus gives the marquee something
        // rich to preview.
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
            cardVerticalPadding: ContinuumTheme.Skyline.rowBandCardVerticalPadding,
            onMoveDown: { pageBand(by: 1) }
        )
        // Natural height so the row hugs its header and top-aligns in the
        // lower-half band rather than stretching.
        .fixedSize(horizontal: false, vertical: true)
        .modifier(rowPagingGeometry(for: section))
    }

    private var nextPreviewSection: ResolvedSection? {
        let nextIndex = pageIndex + 1
        guard sections.indices.contains(nextIndex) else { return nil }
        return sections[nextIndex]
    }

    private var rowStackTransition: AnyTransition {
        guard !reduceMotion, pageTransitionDelta != 0 else {
            return .opacity
        }

        let exitOffset = pageTransitionDelta > 0
            ? -ContinuumTheme.Skyline.rowBandExitOffset
            : ContinuumTheme.Skyline.rowBandExitOffset
        let insertion: AnyTransition = pageTransitionDelta < 0
            ? .offset(y: -ContinuumTheme.Skyline.rowBandExitOffset).combined(with: .opacity)
            : .opacity
        return .asymmetric(
            insertion: insertion,
            removal: .offset(y: exitOffset).combined(with: .opacity)
        )
    }

    private var rowPageAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: ContinuumTheme.fastDuration)
        }
        return .easeInOut(duration: ContinuumTheme.Skyline.rowBandScrollDuration)
    }

    // MARK: - Paging & focus

    /// Page the visible band by ±1. Clamps at the ends; Up past the first
    /// row is handled by the row's onMoveUp (to the top bar). Each page hands
    /// focus to the new row's first card via the focus token.
    private func pageBand(by delta: Int) {
        let target = pageIndex + delta
        guard sections.indices.contains(target) else { return }
        outgoingPageIndex = pageIndex
        pageTransitionDelta = delta
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
        pageTransitionDelta = 0
        outgoingPageIndex = nil
        pageIndex = 0
        contentFocusToken += 1
    }

    private func rowPagingGeometry(for section: ResolvedSection) -> TVRowPagingGeometry {
        TVRowPagingGeometry(
            id: section.id,
            namespace: rowPagingNamespace,
            isEnabled: !reduceMotion
        )
    }

    private func rowStackZIndex(for section: ResolvedSection) -> Double {
        guard pageTransitionDelta != 0,
              let index = sections.firstIndex(where: { $0.id == section.id }) else {
            return 0
        }

        if pageTransitionDelta > 0 {
            return index == outgoingPageIndex ? 1 : 0
        }

        return index == pageIndex ? 1 : 0
    }
}

private struct TVRowPagingGeometry: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .position,
                anchor: .topLeading
            )
        } else {
            content
        }
    }
}

private struct TVSectionRowPreview: View {
    let section: ResolvedSection
    let cardWidth: CGFloat

    private var isContinueWatching: Bool {
        section.sectionType == "continue_watching" || section.sectionType == "in_progress"
    }

    private var isEpisodeRow: Bool {
        let type = section.sectionType.lowercased()
        if type.contains("next") || type.contains("up_next") || type.contains("next_up") {
            return true
        }
        return section.items.contains { $0.type.lowercased() == "episode" }
    }

    private var isAudiobookRow: Bool {
        !section.items.isEmpty && section.items.allSatisfy(\.isAudiobook)
    }

    private var layout: MediaRowLayout {
        if isContinueWatching { return .thumbnail }
        if isEpisodeRow { return .thumbnail }
        if isAudiobookRow { return .square }
        return .poster
    }

    private var showProgress: Bool {
        isContinueWatching || isEpisodeRow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            HStack(spacing: 40) {
                ForEach(Array(section.items.prefix(ContinuumTheme.Skyline.rowPreviewItemLimit))) { item in
                    TVPassivePreviewCard(
                        item: item,
                        layout: layout,
                        showProgress: showProgress,
                        cardWidth: cardWidth
                    )
                }
            }
            .padding(.horizontal, ContinuumTheme.safePadding)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(ContinuumTheme.Skyline.rowPreviewOpacity)
        .allowsHitTesting(false)
        .focusEffectDisabled()
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 14) {
            if isContinueWatching {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.continuumOnSurface)
            }

            Text(section.title)
                .font(.continuumHeadline)
                .foregroundColor(.continuumOnSurface)

            Spacer()
        }
        .padding(.horizontal, ContinuumTheme.safePadding)
    }
}

private struct TVPassivePreviewCard: View {
    let item: SectionItem
    let layout: MediaRowLayout
    let showProgress: Bool
    let cardWidth: CGFloat

    var body: some View {
        switch layout {
        case .poster, .square:
            posterCard
        case .thumbnail:
            thumbnailCard
        }
    }

    private var posterCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            posterArtwork

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.continuumSubheadline)
                    .foregroundColor(.continuumOnSurface.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let year = item.year {
                    Text(String(year))
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                }
            }
            .frame(width: posterWidth, alignment: .leading)
        }
        .frame(width: posterWidth)
    }

    private var thumbnailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            thumbnailArtwork

            VStack(alignment: .leading, spacing: 4) {
                Text(thumbnailTitle)
                    .font(.continuumSubheadline)
                    .foregroundColor(.continuumOnSurface.opacity(0.85))
                    .lineLimit(1)

                if let subtitle = thumbnailSubtitle {
                    Text(subtitle)
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: ContinuumTheme.thumbnailCardWidth, alignment: .leading)
        }
        .frame(width: ContinuumTheme.thumbnailCardWidth)
    }

    private var posterArtwork: some View {
        ZStack(alignment: .bottom) {
            AsyncImageView(
                url: item.posterUrl ?? "",
                thumbhash: item.posterThumbhash,
                targetSize: CGSize(width: posterWidth, height: posterHeight),
                contentMode: .fill
            )
            .frame(width: posterWidth, height: posterHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))

            if let progress = progressValue, progress > 0 {
                VStack {
                    Spacer()
                    ProgressBar(value: progress)
                }
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
            }

            if item.userState?.played == true {
                watchedBadge
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: posterWidth, height: posterHeight)
    }

    private var thumbnailArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImageView(
                url: thumbnailImageURL,
                thumbhash: item.backdropThumbhash ?? item.posterThumbhash,
                targetSize: CGSize(width: ContinuumTheme.thumbnailCardWidth, height: ContinuumTheme.thumbnailCardHeight),
                contentMode: .fill
            )
            .frame(width: ContinuumTheme.thumbnailCardWidth, height: ContinuumTheme.thumbnailCardHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: ContinuumTheme.thumbnailCardWidth, height: ContinuumTheme.thumbnailCardHeight)
            .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))

            if let badge = episodeBadge {
                Text(badge)
                    .font(.continuumCaption)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .padding(14)
            }

            if let progress = progressValue, progress > 0 {
                VStack {
                    Spacer()
                    ProgressBar(value: progress)
                }
                .frame(width: ContinuumTheme.thumbnailCardWidth, height: ContinuumTheme.thumbnailCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius))
            }

            if item.userState?.played == true {
                watchedBadge
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: ContinuumTheme.thumbnailCardWidth, height: ContinuumTheme.thumbnailCardHeight)
    }

    private var watchedBadge: some View {
        ZStack {
            Circle()
                .fill(Color.continuumOnSurface)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.3), radius: 4)
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color.continuumBackground)
        }
    }

    private var posterWidth: CGFloat {
        cardWidth
    }

    private var posterHeight: CGFloat {
        switch layout {
        case .square:
            return cardWidth
        case .poster, .thumbnail:
            return cardWidth * (ContinuumTheme.posterCardHeight / ContinuumTheme.posterCardWidth)
        }
    }

    private var thumbnailImageURL: String {
        if let backdrop = item.backdropUrl, !backdrop.isEmpty {
            return backdrop
        }
        return item.posterUrl ?? ""
    }

    private var thumbnailTitle: String {
        item.seriesTitle ?? item.title
    }

    private var thumbnailSubtitle: String? {
        if item.seriesTitle != nil {
            return item.title
        }
        if let year = item.year {
            return String(year)
        }
        return nil
    }

    private var episodeBadge: String? {
        guard let season = item.seasonNumber, let episode = item.episodeNumber else {
            return nil
        }
        return "S\(season) · E\(episode)"
    }

    private var progressValue: Double? {
        guard showProgress,
              let position = item.positionSeconds,
              let duration = item.durationSeconds,
              duration > 0,
              position > 0 else {
            return nil
        }
        return position / duration
    }
}
#endif
