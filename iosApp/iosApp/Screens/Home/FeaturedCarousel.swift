import SwiftUI
#if os(iOS)
import UIKit
#endif

extension Notification.Name {
    static let featuredCarouselSuspendAutoAdvance = Notification.Name("featuredCarouselSuspendAutoAdvance")
}

/// Shared featured hero used by Home and library Recommended surfaces.
/// Renders a centered landscape card deck over an ambient full-bleed backdrop.
struct FeaturedCarousel: View {
    let items: [SectionItem]
    let onItemTap: (String) -> Void
    let onPlayTap: (String) -> Void
    /// Optional extra inset for the active card's copy. Useful when the hero
    /// sits below overlaid chrome on tvOS and the content needs to clear it.
    var textLeadingInset: CGFloat = 0
    /// Additional top breathing room for hosts that place persistent chrome
    /// over the hero on iOS.
    var extraTopInset: CGFloat = 0
    /// Whether the hero card itself should claim default focus on tvOS.
    var prefersDefaultFocus: Bool = false
    /// Optional sink for the dominant color of the currently-displayed
    /// backdrop. Hosts use this to extend a page-level gradient beyond
    /// the hero so there's no seam between the carousel and the rest
    /// of the scroll view.
    var onBackdropTintChange: ((Color) -> Void)? = nil
    /// Optional sink for the active backdrop's image URL + thumbhash.
    /// Hosts that render their own page-level backdrop layer (e.g.
    /// HomeView) set this to draw a larger blurred image that extends
    /// past the hero without being clipped to the carousel's frame.
    var onBackdropArtworkChange: ((String, String?) -> Void)? = nil
    /// When `false`, the carousel skips its built-in ambient backdrop
    /// and expects the host to render one. Defaults to `true` so
    /// standalone callers (e.g. BrowseView) keep their self-contained look.
    var rendersAmbientBackdrop: Bool = true
    /// Root tvOS pages can opt into a tighter hero that sits cleanly below
    /// the custom top menu.
    var prefersTightTVOSLayout: Bool = false
    /// tvOS focus request token from the hosting shell. Incrementing this
    /// returns the hero to its first card and moves focus back to the card.
    var focusRequest: Int = 0
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil

    @State private var currentPage = 0
    @State private var backdropPage = 0
    @State private var autoAdvanceTimer: Timer?
    @State private var autoAdvanceEnabled = true
    @State private var autoAdvanceCycleStart = Date()
    @State private var stageShift: CGFloat = 0
    @State private var isAnimatingStage = false
    @State private var stageTransitionGeneration: Int = 0
    @State private var tintSampleTask: Task<Void, Never>?
    @State private var lastSampledTintURL: String?
    @Namespace private var heroGlassNamespace
    @EnvironmentObject private var overlayStore: OverlayPrefsStore

    #if os(tvOS)
    @Namespace private var heroActionFocusNamespace
    @FocusState private var actionFocus: ActionFocus?

    private enum ActionFocus: Hashable {
        case heroCard
    }
    #endif

    private let autoAdvanceInterval: TimeInterval = 8.0

    private var stageTransitionAnimation: Animation {
        .easeOut(duration: 0.28)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                GeometryReader { geometry in
                    let metrics = FeaturedCarouselMetrics(
                        containerSize: geometry.size,
                        textLeadingInset: textLeadingInset,
                        extraTopInset: extraTopInset,
                        prefersTightTVOSLayout: prefersTightTVOSLayout
                    )

                    ZStack(alignment: .top) {
                        VStack(spacing: metrics.deckSpacing) {
                            Spacer(minLength: metrics.topInset)

                            deck(metrics: metrics)

                            if items.count > 1 {
                                pageIndicator(metrics: metrics)
                                    .padding(.bottom, metrics.indicatorBottomPadding)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(alignment: .top) {
                        if rendersAmbientBackdrop {
                            ambientBackdrop(metrics: metrics)
                                .ignoresSafeArea(edges: [.top, .horizontal])
                        }
                    }
                }
                .frame(height: preferredHeroHeight)
                #if os(tvOS)
                .ignoresSafeArea(edges: .horizontal)
                #endif
                .onAppear {
                    syncCurrentPage()
                    resetAutoAdvance()
                    refreshBackdropTint()
                    notifyBackdropArtwork()
                    #if os(tvOS)
                    requestHeroFocus(focusRequest)
                    #endif
                }
                .onDisappear {
                    stopAutoAdvance()
                    cancelPendingStageTransition()
                    tintSampleTask?.cancel()
                    tintSampleTask = nil
                }
                .onChange(of: itemIDs) { _, _ in
                    syncCurrentPage()
                    resetAutoAdvance()
                    refreshBackdropTint()
                    notifyBackdropArtwork()
                }
                .onChange(of: backdropPage) { _, _ in
                    refreshBackdropTint()
                    notifyBackdropArtwork()
                }
                #if os(tvOS)
                .onReceive(NotificationCenter.default.publisher(for: .featuredCarouselSuspendAutoAdvance)) { _ in
                    suspendAutoAdvanceForTVInteraction()
                }
                .onChange(of: actionFocus) { _, newValue in
                    guard newValue != nil else { return }
                    suspendAutoAdvanceForTVInteraction()
                }
                .onChange(of: focusRequest) { _, request in
                    requestHeroFocus(request)
                }
                #endif
            }
        }
    }

    private var itemIDs: [String] {
        items.map(\.id)
    }

    private var currentItem: SectionItem {
        items[safe: currentPage] ?? items[0]
    }

    private var backdropItem: SectionItem {
        items[safe: backdropPage] ?? currentItem
    }

    private var stageCards: [FeaturedStageCard] {
        guard !items.isEmpty else { return [] }
        if items.count == 1 {
            return [
                FeaturedStageCard(role: .current, item: items[0])
            ]
        }

        return FeaturedStageRole.allCases.map { role in
            FeaturedStageCard(role: role, item: item(for: role))
        }
    }

    private var preferredHeroHeight: CGFloat {
        #if os(tvOS)
        return 760
        #else
        let screenWidth = PlatformScreen.mainBounds.width
        let screenHeight = PlatformScreen.mainBounds.height
        let widthDriven = max(420, min(screenWidth * 1.16, 580))
        return min(widthDriven, screenHeight * 0.72) + extraTopInset
        #endif
    }

    // MARK: - Backdrop

    private func ambientBackdrop(metrics: FeaturedCarouselMetrics) -> some View {
        ZStack(alignment: .bottom) {
            AsyncImageView(
                url: heroArtworkURL(for: backdropItem),
                thumbhash: heroArtworkThumbhash(for: backdropItem),
                targetSize: CGSize(width: metrics.containerSize.width, height: metrics.backdropHeight),
                contentMode: .fill
            )
            .id(backdropItem.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scaleEffect(metrics.backdropScale)
            .blur(radius: metrics.backdropBlurRadius)
            .transition(.opacity.animation(.easeInOut(duration: 0.55)))

            Rectangle()
                .fill(Color.black.opacity(0.34))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.black.opacity(0.54), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: metrics.topScrimHeight)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // Mask the whole backdrop stack so it fades to transparent
        // before the hero ends. HomeView's page-level tint gradient
        // sits behind this layer, so the hero image dissolves cleanly
        // into the dominant-color wash rather than butting against a
        // hard dark edge.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.55),
                    .init(color: Color.black.opacity(0.6), location: 0.82),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(height: metrics.backdropHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    // MARK: - Deck

    @ViewBuilder
    private func deck(metrics: FeaturedCarouselMetrics) -> some View {
        let content = HStack(spacing: metrics.cardSpacing) {
            ForEach(stageCards) { stageCard in
                heroCard(item: stageCard.item, role: stageCard.role, metrics: metrics)
            }
        }
        .padding(.horizontal, metrics.sideInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: deckOffset(metrics: metrics))

        #if os(iOS)
        content
            .background {
                HorizontalPanGestureAttacher(
                    isEnabled: items.count > 1 && !isAnimatingStage,
                    onChanged: { translation in
                        handleDeckDragChanged(translation: translation, metrics: metrics)
                    },
                    onEnded: { translation, predictedEndTranslation in
                        handleDeckDragEnded(
                            translation: translation,
                            predictedEndTranslation: predictedEndTranslation,
                            metrics: metrics
                        )
                    },
                    onCancelled: {
                        handleDeckDragCancelled()
                    }
                )
            }
        #elseif !os(tvOS)
        content
            .simultaneousGesture(deckDragGesture(metrics: metrics))
        #else
        content
        #endif
    }

    private func deckOffset(metrics: FeaturedCarouselMetrics) -> CGFloat {
        let travel = metrics.cardWidth + metrics.cardSpacing
        return (stageShift - 1) * travel
    }

    #if !os(tvOS)
    private func deckDragGesture(metrics: FeaturedCarouselMetrics) -> some Gesture {
        return DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                handleDeckDragChanged(translation: value.translation, metrics: metrics)
            }
            .onEnded { value in
                handleDeckDragEnded(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    metrics: metrics
                )
            }
    }

    private func handleDeckDragChanged(translation: CGSize, metrics: FeaturedCarouselMetrics) {
        guard items.count > 1, !isAnimatingStage else { return }
        guard abs(translation.width) > abs(translation.height) else { return }
        stopAutoAdvance()

        let travel = metrics.cardWidth + metrics.cardSpacing
        var txn = Transaction()
        txn.disablesAnimations = true
        withTransaction(txn) {
            stageShift = translation.width / travel
        }
    }

    private func handleDeckDragEnded(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        metrics: FeaturedCarouselMetrics
    ) {
        guard items.count > 1, !isAnimatingStage else {
            restartAutoAdvanceIfNeeded()
            return
        }
        guard abs(translation.width) > abs(translation.height) else {
            resetDeckDrag()
            return
        }

        let threshold = metrics.cardWidth * 0.22
        let projectedWidth = predictedEndTranslation.width
        let travelAmount = abs(projectedWidth) > abs(translation.width) ? projectedWidth : translation.width

        if travelAmount < -threshold {
            requestStageMove(.next, wraps: true)
        } else if travelAmount > threshold {
            requestStageMove(.previous, wraps: true)
        } else {
            withAnimation(stageTransitionAnimation) {
                stageShift = 0
            }
        }
        restartAutoAdvanceIfNeeded()
    }

    private func handleDeckDragCancelled() {
        resetDeckDrag()
    }

    private func resetDeckDrag() {
        withAnimation(stageTransitionAnimation) {
            stageShift = 0
        }
        restartAutoAdvanceIfNeeded()
    }
    #endif

    // MARK: - Cards

    private func heroCard(item: SectionItem, role: FeaturedStageRole, metrics: FeaturedCarouselMetrics) -> some View {
        let emphasis = cardEmphasis(for: role)
        let shape = RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)

        return ZStack(alignment: .bottomLeading) {
            AsyncImageView(
                url: heroArtworkURL(for: item),
                thumbhash: heroArtworkThumbhash(for: item),
                targetSize: CGSize(width: metrics.cardWidth, height: metrics.cardHeight),
                contentMode: .fill
            )
            .frame(width: metrics.cardWidth, height: metrics.cardHeight)
            .overlay {
                cardOverlay(emphasis: emphasis)
            }

            // Overlay badges only on the active hero — non-active cards in
            // the deck stay clean. `wide` variant leaves room for the title
            // / actions block that overlaps the bottom corners.
            if role.isActive && overlayStore.enabled {
                CardOverlays(
                    data: OverlayData.from(item),
                    prefs: overlayStore.prefs,
                    variant: .wide
                )
                .frame(width: metrics.cardWidth, height: metrics.cardHeight)
            }

            if emphasis > 0.001 {
                activeCardContent(
                    item: item,
                    role: role,
                    metrics: metrics,
                    emphasis: emphasis,
                    showsActions: role.isActive
                )
            }
        }
        .frame(width: metrics.cardWidth, height: metrics.cardHeight)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                Color.white.opacity(0.08 + (0.10 * emphasis)),
                lineWidth: 0.75 + (0.25 * emphasis)
            )
        }
        .overlay {
            shape.strokeBorder(
                Color.white.opacity(0.06 * emphasis),
                lineWidth: 3
            )
            .blur(radius: 10)
        }
        .scaleEffect(metrics.inactiveScale + ((1 - metrics.inactiveScale) * emphasis))
        .opacity(metrics.inactiveOpacity + ((1 - metrics.inactiveOpacity) * emphasis))
        .offset(y: metrics.inactiveYOffset * (1 - emphasis))
        .zIndex(Double(emphasis))
        .allowsHitTesting(role.isActive)
        .accessibilityHidden(!role.isActive)
        #if os(iOS)
        .contentShape(shape)
        .accessibilityAddTraits(role.isActive ? .isButton : [])
        .onTapGesture {
            guard role.isActive else { return }
            onItemTap(item.contentId)
        }
        #endif
        #if os(tvOS)
        .overlay {
            if role.isActive && actionFocus == .heroCard {
                RoundedRectangle(
                    cornerRadius: metrics.cardCornerRadius + metrics.focusRingOutset,
                    style: .continuous
                )
                    .stroke(Color.white.opacity(0.98), lineWidth: 4)
                    .padding(-metrics.focusRingOutset)
            }
        }
        .overlay {
            if role.isActive && actionFocus == .heroCard {
                RoundedRectangle(
                    cornerRadius: metrics.cardCornerRadius + metrics.focusGlowOutset,
                    style: .continuous
                )
                    .stroke(Color.white.opacity(0.34), lineWidth: 12)
                    .padding(-metrics.focusGlowOutset)
                    .blur(radius: 16)
            }
        }
        .focusScope(heroActionFocusNamespace)
        .focusSection()
        .contentShape(heroFocusShape(metrics: metrics))
        .focusable(role.isActive, interactions: .activate)
        .focused($actionFocus, equals: .heroCard)
        .prefersDefaultFocus(role.isActive && prefersDefaultFocus, in: heroActionFocusNamespace)
        .focusEffectDisabled()
        .accessibilityAddTraits(role.isActive ? .isButton : [])
        .onTapGesture {
            guard role.isActive, actionFocus == .heroCard else { return }
            onItemTap(item.contentId)
        }
        .onMoveCommand { direction in
            guard role.isActive else { return }
            handleHeroCardMove(direction)
        }
        .onPlayPauseCommand {
            guard role.isActive, actionFocus == .heroCard else { return }
            onPlayTap(item.contentId)
        }
        #endif
        #if !os(iOS) && !os(tvOS)
        .contentShape(shape)
        .onTapGesture {
            guard role.isActive else { return }
            onItemTap(item.contentId)
        }
        #endif
    }

    private func cardOverlay(emphasis: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.36),
                    Color.black.opacity(0.56),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(1 - emphasis)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.18), location: 0.0),
                    .init(color: Color.black.opacity(0.26), location: 0.34),
                    .init(color: Color.black.opacity(0.72), location: 0.78),
                    .init(color: Color.black.opacity(0.90), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(emphasis)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.62), location: 0.0),
                    .init(color: Color.black.opacity(0.18), location: 0.38),
                    .init(color: .clear, location: 0.78),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .opacity(emphasis)
        }
    }

    private func activeCardContent(
        item: SectionItem,
        role: FeaturedStageRole,
        metrics: FeaturedCarouselMetrics,
        emphasis: CGFloat,
        showsActions: Bool
    ) -> some View {
        let bodyVisibility = contentVisibility(for: role, emphasis: emphasis)
        let metadataVisibility = metadataVisibility(for: role, emphasis: emphasis)

        return VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            Spacer()

            Group {
                if let eyebrow = eyebrowText(for: item) {
                    Text(eyebrow.uppercased())
                        .font(metrics.eyebrowFont)
                        .tracking(metrics.eyebrowTracking)
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(1)
                }

                titleBlock(item: item, metrics: metrics)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(metrics.overviewFont)
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(metrics.overviewLineLimit)
                        .frame(maxWidth: metrics.textColumnWidth, alignment: .leading)
                }
            }
            .opacity(bodyVisibility)

            chromeCluster(
                item: item,
                metrics: metrics,
                showsActions: showsActions,
                metadataVisibility: metadataVisibility,
                actionVisibility: bodyVisibility
            )
        }
        .padding(.leading, metrics.contentPadding + metrics.textLeadingInset)
        .padding(.trailing, metrics.contentPadding)
        .padding(.top, metrics.contentPadding)
        .padding(.bottom, metrics.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        #if os(tvOS)
        .allowsHitTesting(showsActions)
        #endif
    }

    @ViewBuilder
    private func titleBlock(item: SectionItem, metrics: FeaturedCarouselMetrics) -> some View {
        if let logoUrl = item.logoUrl, !logoUrl.isEmpty {
            AsyncImageView(url: logoUrl, contentMode: .fit)
                .frame(width: metrics.logoMaxWidth, height: metrics.logoHeight, alignment: .leading)
                .accessibilityLabel(item.title)
        } else {
            Text(item.title)
                .font(metrics.titleFont)
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .frame(maxWidth: metrics.textColumnWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chromeCluster(
        item: SectionItem,
        metrics: FeaturedCarouselMetrics,
        showsActions: Bool,
        metadataVisibility: CGFloat,
        actionVisibility: CGFloat
    ) -> some View {
        if #available(iOS 26, tvOS 26, macOS 26, *), showsActions {
            GlassEffectContainer(spacing: metrics.glassSpacing) {
                VStack(alignment: .leading, spacing: metrics.chromeSpacing) {
                    metadataGroup(
                        item: item,
                        metrics: metrics,
                        usesGlass: true,
                        visibility: metadataVisibility
                    )
                    actionArea(
                        item: item,
                        metrics: metrics,
                        usesGlass: true,
                        showsActions: true,
                        visibility: actionVisibility
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: metrics.chromeSpacing) {
                metadataGroup(
                    item: item,
                    metrics: metrics,
                    usesGlass: false,
                    visibility: metadataVisibility
                )
                actionArea(
                    item: item,
                    metrics: metrics,
                    usesGlass: false,
                    showsActions: showsActions,
                    visibility: actionVisibility
                )
            }
        }
    }

    @ViewBuilder
    private func actionArea(
        item: SectionItem,
        metrics: FeaturedCarouselMetrics,
        usesGlass: Bool,
        showsActions: Bool,
        visibility: CGFloat
    ) -> some View {
        #if os(iOS) || os(tvOS)
        EmptyView()
        #else
        actionRow(item: item, metrics: metrics, usesGlass: usesGlass)
            .opacity(visibility)
            .allowsHitTesting(showsActions)
            .accessibilityHidden(!showsActions)
            .frame(height: metrics.actionRowHeight, alignment: .leading)
        #endif
    }

    @ViewBuilder
    private func metadataGroup(
        item: SectionItem,
        metrics: FeaturedCarouselMetrics,
        usesGlass: Bool,
        visibility: CGFloat
    ) -> some View {
        let chips = metadataChips(for: item)
        if chips.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: metrics.chipSpacing) {
                ForEach(chips) { chip in
                    metadataChip(chip, metrics: metrics, usesGlass: usesGlass)
                }
            }
            .frame(maxWidth: metrics.textColumnWidth, alignment: .leading)
            .opacity(visibility)
        }
    }

    @ViewBuilder
    private func metadataChip(_ chip: HeroMetadataChip, metrics: FeaturedCarouselMetrics, usesGlass: Bool) -> some View {
        let content = HStack(spacing: metrics.chipInnerSpacing) {
            if let systemImage = chip.systemImage {
                Image(systemName: systemImage)
                    .font(metrics.chipIconFont)
            }
            Text(chip.title)
                .font(metrics.chipFont)
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.94))
        .padding(.horizontal, metrics.chipHorizontalPadding)
        .padding(.vertical, metrics.chipVerticalPadding)

        if usesGlass, #available(iOS 26, tvOS 26, macOS 26, *) {
            content
                .glassEffect(
                    Glass.regular.tint(Color.white.opacity(0.07)),
                    in: .capsule
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                }
        }
    }

    @ViewBuilder
    private func actionRow(item: SectionItem, metrics: FeaturedCarouselMetrics, usesGlass: Bool) -> some View {
        #if os(tvOS)
        EmptyView()
        #else
        infoButton(item: item, metrics: metrics, usesGlass: usesGlass)
        #endif
    }

    private func infoButton(item: SectionItem, metrics: FeaturedCarouselMetrics, usesGlass: Bool) -> some View {
        return Button {
            onItemTap(item.contentId)
        } label: {
            infoButtonLabel(metrics: metrics)
        }
        .modifier(
            HeroActionButtonModifier(
                isPrimary: false,
                usesGlass: usesGlass,
                namespace: heroGlassNamespace,
                glassID: "hero-more-info-button"
            )
        )
    }

    private func infoButtonLabel(metrics: FeaturedCarouselMetrics) -> some View {
        HStack(spacing: metrics.buttonInnerSpacing) {
            Image(systemName: "info.circle")
                .font(metrics.buttonIconFont)
            Text("More Info")
                .font(metrics.buttonFont)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.buttonHorizontalPadding)
        .padding(.vertical, metrics.buttonVerticalPadding)
    }

    // MARK: - Metadata

    private func metadataChips(for item: SectionItem) -> [HeroMetadataChip] {
        var chips: [HeroMetadataChip] = [
            HeroMetadataChip(id: "type", title: item.type.capitalized, systemImage: nil)
        ]

        if let episodeChip = episodeToken(for: item) {
            chips.append(HeroMetadataChip(id: "episode", title: episodeChip, systemImage: nil))
        }

        if let rating = item.ratingImdb {
            chips.append(
                HeroMetadataChip(
                    id: "rating",
                    title: String(format: "%.1f", rating),
                    systemImage: "star.fill"
                )
            )
        }

        if let year = item.year, year > 0 {
            chips.append(HeroMetadataChip(id: "year", title: String(year), systemImage: nil))
        }

        return chips
    }

    private func eyebrowText(for item: SectionItem) -> String? {
        guard item.type.lowercased() == "episode" else { return nil }
        if let seriesTitle = item.seriesTitle, !seriesTitle.isEmpty {
            return seriesTitle
        }
        return nil
    }

    private func episodeToken(for item: SectionItem) -> String? {
        guard item.type.lowercased() == "episode" else { return nil }
        switch (item.seasonNumber, item.episodeNumber) {
        case let (season?, episode?):
            return "S\(season) E\(episode)"
        case let (season?, nil):
            return "Season \(season)"
        case let (nil, episode?):
            return "Episode \(episode)"
        default:
            return nil
        }
    }

    private func playLabel(for item: SectionItem) -> String {
        let position = item.positionSeconds ?? 0
        let duration = item.durationSeconds ?? 0
        let hasProgress = duration > 0 && position > 60 && (position / duration) < 0.95

        if hasProgress {
            let remaining = max(Int((duration - position) / 60), 1)
            return "Resume · \(remaining) min left"
        }

        return "Play"
    }

    private func heroArtworkURL(for item: SectionItem) -> String {
        if let backdrop = item.backdropUrl, !backdrop.isEmpty {
            return backdrop
        }
        return item.posterUrl ?? ""
    }

    private func heroArtworkThumbhash(for item: SectionItem) -> String? {
        if let backdrop = item.backdropUrl, !backdrop.isEmpty {
            return item.backdropThumbhash
        }
        return item.posterThumbhash
    }

    // MARK: - Indicator

    private func pageIndicator(metrics: FeaturedCarouselMetrics) -> some View {
        #if os(tvOS)
        TimelineView(.periodic(from: autoAdvanceCycleStart, by: 1.0 / 24.0)) { context in
            indicatorRow(metrics: metrics, activeProgress: indicatorProgress(at: context.date))
        }
        #else
        indicatorRow(metrics: metrics, activeProgress: 1)
        #endif
    }

    private func indicatorRow(metrics: FeaturedCarouselMetrics, activeProgress: CGFloat) -> some View {
        HStack(spacing: metrics.indicatorSpacing) {
            ForEach(0..<items.count, id: \.self) { index in
                if index == currentPage {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.24))

                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(metrics.activeIndicatorWidth * activeProgress, metrics.indicatorHeight))
                    }
                    .frame(width: metrics.activeIndicatorWidth, height: metrics.indicatorHeight)
                    .animation(ContinuumTheme.springAnimation, value: currentPage)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.34))
                        .frame(width: metrics.inactiveIndicatorWidth, height: metrics.indicatorHeight)
                        .animation(ContinuumTheme.springAnimation, value: currentPage)
                }
            }
        }
    }

    private func indicatorProgress(at date: Date) -> CGFloat {
        guard autoAdvanceEnabled, items.count > 1 else { return 1 }
        let elapsed = date.timeIntervalSince(autoAdvanceCycleStart)
        let progress = elapsed / autoAdvanceInterval
        return CGFloat(min(max(progress, 0), 1))
    }

    // MARK: - Paging + Timer

    private func syncCurrentPage() {
        cancelPendingStageTransition()
        guard !items.isEmpty else {
            currentPage = 0
            backdropPage = 0
            return
        }

        let clampedPage = min(max(currentPage, 0), items.count - 1)
        currentPage = clampedPage
        backdropPage = clampedPage
    }

    private func resetAutoAdvance() {
        autoAdvanceEnabled = true
        restartAutoAdvanceIfNeeded()
    }

    private func restartAutoAdvanceIfNeeded() {
        guard autoAdvanceEnabled, items.count > 1 else {
            stopAutoAdvance()
            return
        }

        stopAutoAdvance()
        autoAdvanceCycleStart = Date()
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: autoAdvanceInterval, repeats: true) { _ in
            autoAdvanceCycleStart = Date()
            requestStageMove(.next, wraps: true)
        }
    }

    private func stopAutoAdvance() {
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
    }

    // MARK: - Backdrop tint

    private func notifyBackdropArtwork() {
        guard let onBackdropArtworkChange else { return }
        guard !items.isEmpty else { return }
        let url = heroArtworkURL(for: backdropItem)
        guard !url.isEmpty else { return }
        onBackdropArtworkChange(url, heroArtworkThumbhash(for: backdropItem))
    }

    private func refreshBackdropTint() {
        guard let onBackdropTintChange else { return }
        guard !items.isEmpty else { return }

        let urlString = heroArtworkURL(for: backdropItem)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        guard urlString != lastSampledTintURL else { return }

        lastSampledTintURL = urlString
        tintSampleTask?.cancel()
        tintSampleTask = Task { @MainActor in
            let tint = await HeroBackdropPalette.tintColor(for: url)
            guard !Task.isCancelled else {
                if lastSampledTintURL == urlString {
                    lastSampledTintURL = nil
                }
                return
            }
            guard let tint else {
                if lastSampledTintURL == urlString {
                    lastSampledTintURL = nil
                }
                return
            }
            withAnimation(.easeInOut(duration: 0.55)) {
                onBackdropTintChange(tint)
            }
        }
    }

    #if os(tvOS)
    private func heroFocusShape(metrics: FeaturedCarouselMetrics) -> Path {
        Path(CGRect(x: 0, y: 0, width: 48, height: metrics.cardHeight))
    }

    private func handleHeroCardMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            requestStageMove(.previous, wraps: true)
        case .right:
            requestStageMove(.next, wraps: true)
        case .up:
            onMoveUp?()
        case .down:
            onMoveDown?()
        default:
            break
        }
    }

    private func suspendAutoAdvanceForTVInteraction() {
        autoAdvanceEnabled = false
        stopAutoAdvance()
    }

    private func requestHeroFocus(_ request: Int) {
        guard request > 0, !items.isEmpty else { return }
        cancelPendingStageTransition()
        withAnimation(stageTransitionAnimation) {
            currentPage = 0
            backdropPage = 0
            stageShift = 0
            actionFocus = .heroCard
        }
        autoAdvanceEnabled = false
        stopAutoAdvance()
    }
    #endif

    private func requestStageMove(_ direction: FeaturedCarouselDirection, wraps: Bool) {
        guard items.count > 1, !isAnimatingStage else { return }
        guard let targetPage = targetPage(for: direction, wraps: wraps) else { return }

        stageTransitionGeneration &+= 1
        let generation = stageTransitionGeneration
        isAnimatingStage = true
        backdropPage = targetPage

        withAnimation(stageTransitionAnimation) {
            stageShift = direction.stageShift
        } completion: {
            guard generation == stageTransitionGeneration else { return }
            completeStageMove(to: targetPage)
        }
    }

    private func completeStageMove(to targetPage: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentPage = targetPage
            backdropPage = targetPage
            stageShift = 0
        }
        isAnimatingStage = false
    }

    private func cancelPendingStageTransition() {
        stageTransitionGeneration &+= 1
        isAnimatingStage = false

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stageShift = 0
        }
    }

    private func targetPage(for direction: FeaturedCarouselDirection, wraps: Bool) -> Int? {
        guard !items.isEmpty else { return nil }
        let candidate = currentPage + direction.pageDelta
        if wraps {
            return wrappedPage(candidate)
        }
        guard items.indices.contains(candidate) else { return nil }
        return candidate
    }

    private func item(for role: FeaturedStageRole) -> SectionItem {
        switch role {
        case .previous:
            return items[wrappedPage(currentPage - 1)]
        case .current:
            return currentItem
        case .next:
            return items[wrappedPage(currentPage + 1)]
        }
    }

    private func wrappedPage(_ index: Int) -> Int {
        guard !items.isEmpty else { return 0 }
        let remainder = index % items.count
        return remainder >= 0 ? remainder : remainder + items.count
    }

    private func cardEmphasis(for role: FeaturedStageRole) -> CGFloat {
        let progress = min(max(abs(stageShift), 0), 1)

        switch role {
        case .current:
            return 1 - progress
        case .previous:
            return stageShift > 0 ? progress : 0
        case .next:
            return stageShift < 0 ? progress : 0
        }
    }

    private func contentVisibility(for role: FeaturedStageRole, emphasis: CGFloat) -> CGFloat {
        switch role {
        case .current:
            // Outgoing card during a transition: keep copy fully visible so it
            // doesn't blink on its way out — the card image cross-dissolve
            // handles the swap.
            return 1
        case .previous, .next:
            return min(max(emphasis, 0), 1)
        }
    }

    private func metadataVisibility(for role: FeaturedStageRole, emphasis: CGFloat) -> CGFloat {
        switch role {
        case .current:
            return 1
        case .previous, .next:
            return min(max(emphasis, 0), 1)
        }
    }
}

#if os(iOS)
private struct HorizontalPanGestureAttacher: UIViewRepresentable {
    let isEnabled: Bool
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize, CGSize) -> Void
    let onCancelled: () -> Void

    func makeUIView(context: Context) -> HorizontalPanGestureAttachmentView {
        let view = HorizontalPanGestureAttachmentView()
        view.configure(
            isEnabled: isEnabled,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
        return view
    }

    func updateUIView(_ view: HorizontalPanGestureAttachmentView, context: Context) {
        view.configure(
            isEnabled: isEnabled,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }
}

private final class HorizontalPanGestureAttachmentView: UIView, UIGestureRecognizerDelegate {
    private let projectedEndDuration: CGFloat = 0.18
    private let panRecognizer: UIPanGestureRecognizer
    private weak var attachedWindow: UIWindow?

    private var isPanEnabled = true
    private var onChanged: (CGSize) -> Void = { _ in }
    private var onEnded: (CGSize, CGSize) -> Void = { _, _ in }
    private var onCancelled: () -> Void = {}

    override init(frame: CGRect) {
        panRecognizer = UIPanGestureRecognizer()
        super.init(frame: frame)

        backgroundColor = .clear
        isUserInteractionEnabled = false

        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        panRecognizer.delegate = self
        panRecognizer.cancelsTouchesInView = false
        panRecognizer.delaysTouchesBegan = false
        panRecognizer.delaysTouchesEnded = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        detachFromWindow()
    }

    func configure(
        isEnabled: Bool,
        onChanged: @escaping (CGSize) -> Void,
        onEnded: @escaping (CGSize, CGSize) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        isPanEnabled = isEnabled
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.onCancelled = onCancelled
        attachToWindowIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachToWindowIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachToWindowIfNeeded()
    }

    private func attachToWindowIfNeeded() {
        guard let window else {
            detachFromWindow()
            return
        }
        guard attachedWindow !== window else { return }

        detachFromWindow()
        attachedWindow = window
        window.addGestureRecognizer(panRecognizer)
    }

    private func detachFromWindow() {
        attachedWindow?.removeGestureRecognizer(panRecognizer)
        attachedWindow = nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === panRecognizer, isPanEnabled else { return false }
        guard bounds.width > 0, bounds.height > 0 else { return false }
        return bounds.contains(touch.location(in: self))
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panRecognizer, isPanEnabled else { return false }

        let targetView = attachedWindow ?? self
        let velocity = panRecognizer.velocity(in: targetView)
        let translation = panRecognizer.translation(in: targetView)

        if abs(velocity.x) + abs(velocity.y) > 0.1 {
            return abs(velocity.x) > abs(velocity.y)
        }
        return abs(translation.x) > abs(translation.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let targetView = attachedWindow ?? self
        let translation = recognizer.translation(in: targetView)
        let translationSize = CGSize(width: translation.x, height: translation.y)

        switch recognizer.state {
        case .began, .changed:
            onChanged(translationSize)
        case .ended:
            let velocity = recognizer.velocity(in: targetView)
            let projectedEndTranslation = CGSize(
                width: translation.x + velocity.x * projectedEndDuration,
                height: translation.y + velocity.y * projectedEndDuration
            )
            onEnded(translationSize, projectedEndTranslation)
        case .cancelled, .failed:
            onCancelled()
        case .possible:
            break
        @unknown default:
            onCancelled()
        }
    }
}
#endif

// MARK: - Metrics

private struct FeaturedCarouselMetrics {
    let containerSize: CGSize
    let textLeadingInset: CGFloat
    let extraTopInset: CGFloat
    let prefersTightTVOSLayout: Bool

    var heroHeight: CGFloat { containerSize.height }

    #if os(tvOS)
    var backdropHeight: CGFloat { max(containerSize.height + 420, 1080) }
    var backdropBlurRadius: CGFloat { 26 }
    var backdropScale: CGFloat { 1.12 }
    var topInset: CGFloat { prefersTightTVOSLayout ? 128 : 112 }
    var cardWidth: CGFloat {
        prefersTightTVOSLayout
            ? min(containerSize.width * 0.82, 1560)
            : min(containerSize.width * 0.8, 1520)
    }
    var cardHeight: CGFloat {
        prefersTightTVOSLayout
            ? min(containerSize.height * 0.75, 600)
            : min(containerSize.height * 0.82, 660)
    }
    var cardSpacing: CGFloat { 28 }
    var sideInset: CGFloat { max((containerSize.width - cardWidth) / 2, 0) }
    var cardCornerRadius: CGFloat { 34 }
    var focusRingOutset: CGFloat { 8 }
    var focusGlowOutset: CGFloat { 14 }
    var inactiveScale: CGFloat { 0.96 }
    var inactiveOpacity: Double { 0.7 }
    var inactiveYOffset: CGFloat { 8 }
    var deckSpacing: CGFloat { 20 }
    var deckBottomPadding: CGFloat { 0 }
    var indicatorBottomPadding: CGFloat { 18 }
    var indicatorSpacing: CGFloat { 10 }
    var activeIndicatorWidth: CGFloat { 38 }
    var inactiveIndicatorWidth: CGFloat { 12 }
    var indicatorHeight: CGFloat { 10 }
    var topScrimHeight: CGFloat { 220 }
    var contentPadding: CGFloat { 42 }
    var contentSpacing: CGFloat { 20 }
    var chromeSpacing: CGFloat { 16 }
    var glassSpacing: CGFloat { 18 }
    var textColumnWidth: CGFloat { min(cardWidth * 0.58, 720) }
    var logoHeight: CGFloat { 136 }
    var logoMaxWidth: CGFloat { min(cardWidth * 0.44, 520) }
    var titleFont: Font { .system(size: 64, weight: .heavy).leading(.tight) }
    var overviewFont: Font { .system(size: 24, weight: .regular) }
    var overviewLineLimit: Int { 3 }
    var eyebrowFont: Font { .system(size: 18, weight: .bold) }
    var eyebrowTracking: CGFloat { 1.8 }
    var chipSpacing: CGFloat { 12 }
    var chipInnerSpacing: CGFloat { 8 }
    var chipHorizontalPadding: CGFloat { 18 }
    var chipVerticalPadding: CGFloat { 12 }
    var chipFont: Font { .system(size: 20, weight: .semibold) }
    var chipIconFont: Font { .system(size: 18, weight: .semibold) }
    var actionSpacing: CGFloat { 18 }
    var actionRowHeight: CGFloat { 84 }
    var buttonInnerSpacing: CGFloat { 10 }
    var buttonHorizontalPadding: CGFloat { 24 }
    var buttonVerticalPadding: CGFloat { 15 }
    var buttonFont: Font { .system(size: 20, weight: .semibold) }
    var buttonIconFont: Font { .system(size: 18, weight: .bold) }
    #else
    var backdropHeight: CGFloat { heroHeight }
    var backdropBlurRadius: CGFloat { 0 }
    var backdropScale: CGFloat { 1.04 }
    var topInset: CGFloat { 92 + extraTopInset }
    var cardWidth: CGFloat { min(containerSize.width - 32, 780) }
    var cardHeight: CGFloat { min(max(containerSize.width * 0.84, 300), 390) }
    var cardSpacing: CGFloat { 18 }
    var sideInset: CGFloat { max((containerSize.width - cardWidth) / 2, 0) }
    var cardCornerRadius: CGFloat { 28 }
    var inactiveScale: CGFloat { 0.92 }
    var inactiveOpacity: Double { 0.46 }
    var inactiveYOffset: CGFloat { 18 }
    var deckSpacing: CGFloat { 8 }
    var deckBottomPadding: CGFloat { 0 }
    var indicatorBottomPadding: CGFloat { 4 }
    var indicatorSpacing: CGFloat { 8 }
    var activeIndicatorWidth: CGFloat { 22 }
    var inactiveIndicatorWidth: CGFloat { 8 }
    var indicatorHeight: CGFloat { 8 }
    var topScrimHeight: CGFloat { 120 }
    var contentPadding: CGFloat { 20 }
    var contentSpacing: CGFloat { 12 }
    var chromeSpacing: CGFloat { 12 }
    var glassSpacing: CGFloat { 14 }
    var textColumnWidth: CGFloat { min(cardWidth * 0.82, 380) }
    var logoHeight: CGFloat { 74 }
    var logoMaxWidth: CGFloat { min(cardWidth * 0.52, 250) }
    var titleFont: Font { .system(size: 32, weight: .heavy).leading(.tight) }
    var overviewFont: Font { .system(size: 15, weight: .regular) }
    var overviewLineLimit: Int { 3 }
    var eyebrowFont: Font { .system(size: 11, weight: .bold) }
    var eyebrowTracking: CGFloat { 1.0 }
    var chipSpacing: CGFloat { 8 }
    var chipInnerSpacing: CGFloat { 5 }
    var chipHorizontalPadding: CGFloat { 12 }
    var chipVerticalPadding: CGFloat { 8 }
    var chipFont: Font { .system(size: 12, weight: .semibold) }
    var chipIconFont: Font { .system(size: 11, weight: .semibold) }
    var actionSpacing: CGFloat { 10 }
    var actionRowHeight: CGFloat { 44 }
    var buttonInnerSpacing: CGFloat { 8 }
    var buttonHorizontalPadding: CGFloat { 16 }
    var buttonVerticalPadding: CGFloat { 10 }
    var buttonFont: Font { .system(size: 14, weight: .semibold) }
    var buttonIconFont: Font { .system(size: 12, weight: .bold) }
    #endif
}

// MARK: - Action styling

private struct HeroActionButtonModifier: ViewModifier {
    let isPrimary: Bool
    let usesGlass: Bool
    let namespace: Namespace.ID
    let glassID: String

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .buttonStyle(HeroFallbackButtonStyle(isPrimary: isPrimary))
        #else
        content
            .buttonStyle(HeroFallbackButtonStyle(isPrimary: isPrimary))
        #endif
    }
}

private struct HeroFallbackButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        HeroFallbackButtonBody(configuration: configuration, isPrimary: isPrimary)
    }
}

private struct HeroFallbackButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isPrimary: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(foregroundColor)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay {
                Capsule()
                    .stroke(innerBorderColor, lineWidth: innerBorderWidth)
            }
            .overlay {
                #if os(tvOS)
                if isFocused {
                    Capsule()
                        .stroke(focusOutlineColor, lineWidth: focusOutlineWidth)
                        .padding(-focusOutlineInset)
                }
                #endif
            }
            .scaleEffect(scale)
            .shadow(
                color: focusShadowColor,
                radius: focusShadowRadius,
                y: focusShadowYOffset
            )
            .shadow(
                color: focusGlowColor,
                radius: focusGlowRadius,
                y: 0
            )
            #if os(tvOS)
            .focusEffectDisabled()
            #endif
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
            .animation(ContinuumTheme.springAnimation, value: isFocused)
    }

    private var foregroundColor: Color {
        #if os(tvOS)
        if isPrimary { return .black }
        return isFocused ? .black : .white
        #else
        if isPrimary { return .black }
        return .white
        #endif
    }

    private var backgroundColor: Color {
        #if os(tvOS)
        if isPrimary {
            return isFocused ? .white : Color.white.opacity(0.76)
        }
        return isFocused ? .white : Color.black.opacity(0.52)
        #else
        if isPrimary {
            return isFocused ? Color.white.opacity(0.94) : Color.white
        }
        return Color.continuumSurfaceElevated.opacity(isFocused ? 0.96 : 0.84)
        #endif
    }

    private var innerBorderColor: Color {
        #if os(tvOS)
        if isFocused {
            return Color.black.opacity(isPrimary ? 0.18 : 0.12)
        }
        return isPrimary ? Color.white.opacity(0.12) : Color.white.opacity(0.24)
        #else
        return isPrimary ? Color.white.opacity(0.18) : Color.white.opacity(isFocused ? 0.18 : 0.12)
        #endif
    }

    private var innerBorderWidth: CGFloat {
        #if os(tvOS)
        if isFocused {
            return isPrimary ? 1.8 : 1.5
        }
        return isPrimary ? 0.8 : 1.2
        #else
        isFocused ? 1.0 : 0.8
        #endif
    }

    private var focusOutlineColor: Color {
        isPrimary ? Color.white.opacity(0.94) : Color.white.opacity(0.98)
    }

    private var focusOutlineWidth: CGFloat {
        isPrimary ? 4 : 3.5
    }

    private var focusOutlineInset: CGFloat {
        isPrimary ? 7 : 6
    }

    private var scale: CGFloat {
        #if os(tvOS)
        let base: CGFloat = isFocused ? (isPrimary ? 1.085 : 1.06) : 1.0
        return configuration.isPressed ? base * 0.98 : base
        #else
        return configuration.isPressed ? 0.98 : 1.0
        #endif
    }

    private var focusShadowColor: Color {
        #if os(tvOS)
        switch isPrimary {
        case true: return .black.opacity(isFocused ? 0.42 : 0.20)
        case false: return .black.opacity(isFocused ? 0.36 : 0.18)
        }
        #else
        return isFocused ? .black.opacity(0.32) : .clear
        #endif
    }

    private var focusShadowRadius: CGFloat {
        #if os(tvOS)
        if isPrimary {
            return isFocused ? 24 : 6
        }
        return isFocused ? 20 : 4
        #else
        return isFocused ? 18 : 0
        #endif
    }

    private var focusShadowYOffset: CGFloat {
        #if os(tvOS)
        return isFocused ? 10 : 2
        #else
        return isFocused ? 10 : 0
        #endif
    }

    private var focusGlowColor: Color {
        #if os(tvOS)
        return Color.continuumOnSurface.opacity(isFocused ? 0.18 : 0)
        #else
        return .clear
        #endif
    }

    private var focusGlowRadius: CGFloat {
        #if os(tvOS)
        guard isFocused else { return 0 }
        return isPrimary ? 14 : 12
        #else
        return 0
        #endif
    }
}

// MARK: - Supporting types

private struct HeroMetadataChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
}

private enum FeaturedCarouselDirection {
    case previous
    case next

    var pageDelta: Int {
        switch self {
        case .previous: return -1
        case .next: return 1
        }
    }

    var stageShift: CGFloat {
        switch self {
        case .previous: return 1
        case .next: return -1
        }
    }
}

private enum FeaturedStageRole: String, CaseIterable, Identifiable {
    case previous
    case current
    case next

    var id: String { rawValue }

    var isActive: Bool { self == .current }
}

private struct FeaturedStageCard: Identifiable {
    let role: FeaturedStageRole
    let item: SectionItem

    var id: String { role.id }
}

// MARK: - Optional external focus binding for the play button

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
