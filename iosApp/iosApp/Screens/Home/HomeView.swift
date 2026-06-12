import SwiftUI

extension Notification.Name {
    static let homeSectionsShouldRefresh = Notification.Name("homeSectionsShouldRefresh")
}

/// Main home screen. iOS/macOS keep the featured carousel above the
/// section rows; tvOS replaced it with the Skyline focus marquee (§5.4) —
/// a passive billboard previewing whichever card holds focus.
struct HomeView: View {
    var homeFocusRequest: Int = 0
    /// tvOS-only: whether the custom top menu holds focus. Deferred entry
    /// claims are dropped while the user is up in the menu so late data
    /// loads never yank focus.
    var isTopMenuFocused: Bool = false
    var onTopMenuFocusRequest: (() -> Void)? = nil

    @State private var viewModel = HomeViewModel()
    #if os(tvOS)
    /// Skyline folded the For You root into Home (§4.1): its rows render
    /// after Continue Watching, reusing the recommendations data source.
    @State private var recommendationsViewModel = RecommendationsViewModel()
    #endif
    #if !os(tvOS)
    @State private var heroTintColor: Color = .continuumBackground
    @State private var heroBackdropURL: String?
    @State private var heroBackdropThumbhash: String?
    @State private var currentProfile: UserProfile?
    @State private var homeScrollOffset: CGFloat = 0
    @State private var isRefreshing = false
    @State private var refreshStartedAt: Date?
    @State private var refreshHideTask: Task<Void, Never>?
    private let chromeFadeDistance: CGFloat = 72
    #else
    /// Entry tokens that arrived before any row existed to claim them —
    /// sections mount async, so the initial hand-down would land on nothing.
    @State private var pendingHomeFocusRequest: Int?
    /// Token handed to row 1 so its first card claims focus on entry.
    @State private var rowFocusToken = 0
    /// Debounced focused-card state driving the marquee + backdrop.
    @State private var marqueeModel = TVFocusMarqueeModel()
    #endif
    @Environment(AppRouter.self) private var router
    @Environment(AudioPlaybackStore.self) private var audioStore

    #if !os(tvOS)
    /// How far the blurred page backdrop extends below the hero's
    /// visible bottom edge. The extra vertical room lets the image's
    /// mask finish its fade well after the carousel's cards end, so
    /// there's no seam where the poster stops and the rest of the
    /// page begins.
    private let heroBackdropFadeExtension: CGFloat = 260

    private let heroBackdropHorizontalBleed: CGFloat = 0
    #endif

    var body: some View {
        // On iOS the top bar overlays the hero backdrop — the scroll content
        // extends behind the status bar and the header floats on top with a
        // semi-transparent fill. On tvOS the app-level top bar (owned by
        // `TVMainTabView`) handles profile + utility actions; Home renders
        // the focus marquee over rows, with the backdrop tracking whichever
        // card holds focus (§5.4).
        #if os(tvOS)
        ZStack(alignment: .top) {
            TVRootHeroBackdrop(
                tintColor: marqueeModel.tintColor,
                artworkURL: marqueeModel.content?.backdropUrl,
                artworkThumbhash: marqueeModel.content?.backdropThumbhash,
                isVisible: marqueeModel.content != nil,
                crossfadeDuration: ContinuumTheme.Skyline.marqueeCrossfadeDuration
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Above the rows so the billboard always reads at the top of
            // the screen; never focusable and never hit-testable.
            TVFocusMarquee(content: marqueeModel.content, scale: .home)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            async let sectionsLoad: Void = viewModel.loadSections()
            async let recommendationsLoad: Void = recommendationsViewModel.loadRecommendations()
            _ = await (sectionsLoad, recommendationsLoad)
        }
        .onAppear {
            // Refresh on return (e.g. after player dismiss) so
            // Continue Watching reflects new progress. Skip the
            // very first appear — `.task` handles the initial
            // load and we don't want two concurrent fetches.
            guard !viewModel.sections.isEmpty else { return }
            Task { await viewModel.loadSections() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeSectionsShouldRefresh)) { _ in
            Task { await viewModel.loadSections() }
        }
        #else
        ZStack(alignment: .top) {
            heroTintBackground
            heroBackdropImage

            Group {
                if viewModel.sections.isEmpty {
                    if let error = viewModel.error {
                        ErrorView(state: error, onRetry: { Task { await viewModel.loadSections() } })
                    } else {
                        Color.clear
                    }
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Let the scroll content (and the hero backdrop inside it) extend
            // up behind the status bar so the overlay header reads as floating
            // on top of the image.
            .ignoresSafeArea(edges: .top)

            HStack(spacing: 12) {
                SidebarToggleButton()

                Text("Home")
                    .font(.continuumTitle)
                    .foregroundColor(.continuumOnSurface)

                Spacer(minLength: 8)

                TabTopBarActions(
                    profile: currentProfile,
                    onSearch: { router.navigate(to: .search) },
                    onSwitchProfile: {
                        AuthService.shared.profileId = nil
                        router.showProfileSelection()
                    },
                    onSwitchServer: { router.navigate(to: .serverList) },
                    onSignOut: { router.signOutAndReset() }
                )
            }
            .padding(.horizontal, ContinuumTheme.padding)
            .padding(.top, ContinuumTheme.smallPadding)
            .padding(.bottom, ContinuumTheme.smallPadding)
            .background {
                homeHeaderChrome
                    .opacity(headerChromeOpacity)
                    .ignoresSafeArea(edges: .top)
            }

            if isRefreshing {
                RefreshStatusPill()
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isRefreshing)
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task {
            await viewModel.loadSections()
            await loadCurrentProfile()
        }
        .refreshable {
            await refreshHome()
        }
        #endif
    }

    #if !os(tvOS)
    /// Plex-style page-level gradient. Starts at the sampled dominant
    /// color of the active featured backdrop and fades into the OLED
    /// black base. Because this layer sits behind the scroll view the
    /// tint stretches beneath every row — the hero blends into the
    /// rest of the screen instead of leaving a seam where the ambient
    /// backdrop stops.
    private var heroTintBackground: some View {
        LinearGradient(
            stops: [
                .init(color: heroTintColor, location: 0.0),
                .init(color: heroTintColor.opacity(0.55), location: 0.35),
                .init(color: .continuumBackground, location: 0.8),
                .init(color: .continuumBackground, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.55), value: heroTintColor)
        .ignoresSafeArea()
    }

    /// Blurred full-bleed backdrop that lives at the page level so it
    /// can extend past the hero's height. The mask fades the image
    /// out gradually into the `heroTintBackground` gradient below, so
    /// there's no hard edge where the poster ends.
    @ViewBuilder
    private var heroBackdropImage: some View {
        let totalHeight = computedHeroHeight + heroBackdropFadeExtension
        GeometryReader { geometry in
            let visibleWidth = geometry.size.width
            let paintedWidth = visibleWidth + heroBackdropHorizontalBleed

            Color.clear
                .frame(width: visibleWidth, height: totalHeight, alignment: .top)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        if let url = heroBackdropURL, !url.isEmpty {
                            AsyncImageView(
                                url: url,
                                thumbhash: heroBackdropThumbhash,
                                targetSize: CGSize(width: paintedWidth, height: totalHeight),
                                contentMode: .fill
                            )
                            .id(url)
                            .frame(width: paintedWidth, height: totalHeight, alignment: .top)
                            .scaleEffect(1.04)
                            .blur(radius: 22)
                            .transition(.opacity.animation(.easeInOut(duration: 0.55)))

                            Rectangle()
                                .fill(Color.black.opacity(0.34))
                                .frame(width: paintedWidth, height: totalHeight)

                            LinearGradient(
                                colors: [.black.opacity(0.54), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 140)
                            .frame(width: paintedWidth, alignment: .top)
                        }
                    }
                    .frame(width: paintedWidth, height: totalHeight, alignment: .top)
                    .mask {
                        heroBackdropFadeMask
                            .frame(width: paintedWidth, height: totalHeight)
                    }
                }
        }
        .frame(height: totalHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .allowsHitTesting(false)
    }

    private var heroBackdropFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.42),
                .init(color: Color.black.opacity(0.7), location: 0.66),
                .init(color: Color.black.opacity(0.25), location: 0.86),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Mirrors `FeaturedCarousel.preferredHeroHeight` so the page-level
    /// backdrop image knows how tall to draw before the fade region
    /// starts. Keep these in sync.
    private var computedHeroHeight: CGFloat {
        let screenWidth = PlatformScreen.mainBounds.width
        let screenHeight = PlatformScreen.mainBounds.height
        let widthDriven = max(420, min(screenWidth * 1.16, 580))
        return min(widthDriven, screenHeight * 0.72)
    }
    #endif

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.sections.isEmpty {
            if let error = viewModel.error {
                ErrorView(state: error, onRetry: { Task { await viewModel.loadSections() } })
            } else {
                Color.clear
            }
        } else {
            scrollContent
        }
    }

    #if os(tvOS)
    /// Rows-only scroll under the fixed marquee (§6.1): no carousel, no
    /// dots, no hero buttons. The viewport starts at the §5.7 row slot so
    /// rows scrolling up disappear beneath the marquee instead of
    /// colliding with its text.
    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: sectionSpacing, pinnedViews: []) {
                ForEach(Array(displayedSections.enumerated()), id: \.element.id) { index, section in
                    SectionRow(
                        section: section,
                        onItemTap: { navigateToDetail($0) },
                        prefersDefaultFocusOnFirstItem: index == 0,
                        focusRequest: index == 0 ? rowFocusToken : 0,
                        onMoveUp: index == 0 ? onTopMenuFocusRequest : nil,
                        onItemFocus: { item in
                            marqueeModel.preview(TVMarqueeContent(item: item, rowTitle: section.title))
                        }
                    )
                    // Identity stays keyed on the section id alone so
                    // late-arriving rows (the folded recommendations)
                    // can insert above without rebuilding — and
                    // potentially defocusing — the rows already on
                    // screen.
                    .id(HomeFocusTarget.row(section.id))
                }
            }
            .padding(.bottom, ContinuumTheme.largePadding)
        }
        .padding(.top, ContinuumTheme.Skyline.homeFirstRowTop)
        .onAppear {
            requestHomeFocus(homeFocusRequest)
        }
        .onChange(of: homeFocusRequest) { _, request in
            requestHomeFocus(request)
        }
        .onChange(of: viewModel.sections.map(\.id)) { _, _ in
            guard let request = pendingHomeFocusRequest else { return }
            requestHomeFocus(request)
        }
    }
    #else
    private var scrollContent: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: sectionSpacing, pinnedViews: []) {
                    // Featured carousel
                    if let featured = viewModel.featuredSection {
                        FeaturedCarousel(
                            items: featured.items,
                            onItemTap: { navigateToDetail($0) },
                            onPlayTap: { navigateToPlayer($0) },
                            prefersDefaultFocus: true,
                            onBackdropTintChange: { heroTintColor = $0 },
                            onBackdropArtworkChange: { url, thumbhash in
                                withAnimation(.easeInOut(duration: 0.65)) {
                                    heroBackdropURL = url
                                    heroBackdropThumbhash = thumbhash
                                }
                            },
                            rendersAmbientBackdrop: false,
                            focusRequest: homeFocusRequest,
                            onMoveUp: onTopMenuFocusRequest
                        )
                        .id(HomeFocusTarget.featured)
                    } else {
                        // No hero → reserve enough runway for the floating
                        // Home header so the first row doesn't slide under
                        // the status bar chrome on phones.
                        Color.clear.frame(height: noFeaturedTopSpacing(topSafeAreaInset: geometry.safeAreaInsets.top))
                            .id(HomeFocusTarget.noFeaturedTopSpacer)
                    }

                    // Regular sections
                    ForEach(Array(displayedSections.enumerated()), id: \.element.id) { index, section in
                        SectionRow(
                            section: section,
                            onItemTap: { navigateToDetail($0) },
                            prefersDefaultFocusOnFirstItem: index == 0,
                            onMoveUp: viewModel.featuredSection == nil && index == 0 ? onTopMenuFocusRequest : nil
                        )
                        .id(HomeFocusTarget.row(section.id))
                    }
                }
                .padding(.bottom, ContinuumTheme.largePadding)
            }
        }
        // Keep the overlay chrome transparent at rest, then fade in a subtle
        // glass surface once content has moved underneath it.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            homeScrollOffset = max(0, newValue)
        }
    }
    #endif

    private enum HomeFocusTarget: Hashable {
        case featured
        case noFeaturedTopSpacer
        case row(String)
    }

    /// Rows for the vertical list. On tvOS the For You recommendation rows
    /// fold in right after Continue Watching (Skyline §6.1); other
    /// platforms keep their dedicated Recommendations tab.
    private var displayedSections: [ResolvedSection] {
        #if os(tvOS)
        let home = viewModel.regularSections
        let recommendations = recommendationsViewModel.sections
            .filter { !$0.items.isEmpty }
            .map { section in
                // Re-key so a recommendations row can never collide with a
                // home row that shares the same server section id.
                ResolvedSection(
                    id: "rec:\(section.id)",
                    sectionType: section.sectionType,
                    title: section.title,
                    featured: false,
                    itemLimit: section.itemLimit,
                    totalCount: section.totalCount,
                    isCustom: section.isCustom,
                    customized: section.customized,
                    items: section.items
                )
            }
        guard !recommendations.isEmpty else { return home }

        let continueWatchingIndex = home.lastIndex(where: {
            $0.sectionType == "continue_watching" || $0.sectionType == "in_progress"
        })
        var merged = home
        merged.insert(
            contentsOf: recommendations,
            at: continueWatchingIndex.map { $0 + 1 } ?? 0
        )
        return merged
        #else
        return viewModel.regularSections
        #endif
    }

    #if os(tvOS)
    /// Entry focus → the first card of the first row (§6.1) — typically
    /// Continue Watching — which the marquee previews immediately.
    /// Tokens that arrive before the rows exist wait for the section
    /// load; deferred claims are dropped if the user has meanwhile moved
    /// up into the menu, so a late fetch never steals focus.
    private func requestHomeFocus(_ request: Int) {
        guard request > 0 else { return }
        guard !displayedSections.isEmpty else {
            pendingHomeFocusRequest = request
            return
        }

        let wasDeferred = pendingHomeFocusRequest != nil
        pendingHomeFocusRequest = nil
        if wasDeferred, isTopMenuFocused { return }
        rowFocusToken += 1
    }
    #endif

    #if !os(tvOS)
    private var headerChromeOpacity: Double {
        let progress = min(max(homeScrollOffset / chromeFadeDistance, 0), 1)
        return Double(progress)
    }

    @ViewBuilder
    private var homeHeaderChrome: some View {
        let borderOpacity = 0.06 + (0.04 * headerChromeOpacity)

        if #available(iOS 26, macOS 26, *) {
            Color.clear
                .glassEffect(
                    Glass.regular.tint(Color.black.opacity(0.08)),
                    in: .rect
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(borderOpacity))
                        .frame(height: 0.75)
                }
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Color.continuumSurfaceElevated.opacity(0.32)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(borderOpacity))
                        .frame(height: 0.75)
                }
        }
    }

    private func refreshHome() async {
        await MainActor.run {
            showRefreshStatus()
        }

        await viewModel.loadSections()

        await MainActor.run {
            scheduleRefreshStatusHide()
        }
    }

    private func showRefreshStatus() {
        refreshHideTask?.cancel()
        refreshStartedAt = Date()
        isRefreshing = true
    }

    private func scheduleRefreshStatusHide() {
        let elapsed = Date().timeIntervalSince(refreshStartedAt ?? Date())
        let remaining = RefreshStatusPill.minimumVisibleDuration - elapsed
        refreshHideTask?.cancel()
        refreshHideTask = Task { @MainActor in
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }

            isRefreshing = false
            refreshStartedAt = nil
            refreshHideTask = nil
        }
    }

    /// Load the currently-selected profile so we can render its avatar in
    /// the top bar. Non-fatal on failure — we fall back to a generic icon.
    private func loadCurrentProfile() async {
        guard let profileId = AuthService.shared.profileId else { return }
        do {
            let profiles = try await AuthService.shared.getProfiles()
            currentProfile = profiles.first(where: { $0.id == profileId })
        } catch {
            // Leave currentProfile nil; the top bar renders a fallback.
        }
    }
    #endif

    // MARK: - Navigation

    private func navigateToDetail(_ contentId: String) {
        router.navigate(to: .itemDetail(contentId: contentId))
    }

    #if !os(tvOS)
    /// Hero-card play action. tvOS has no carousel anymore — pressing a
    /// focused card opens it via `onItemTap`, and resume lives on detail.
    private func navigateToPlayer(_ item: SectionItem) {
        if item.isAudiobook {
            audioStore.play(contentId: item.contentId)
            return
        }

        router.presentPlayer(contentId: item.contentId)
    }
    #endif

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        return 30
        #else
        return ContinuumTheme.largePadding
        #endif
    }

    #if !os(tvOS)
    private func noFeaturedTopSpacing(topSafeAreaInset: CGFloat) -> CGFloat {
        let headerContentHeight: CGFloat = 40 + (ContinuumTheme.smallPadding * 2)
        return topSafeAreaInset + headerContentHeight + ContinuumTheme.largePadding + ContinuumTheme.smallPadding
    }
    #endif
}
