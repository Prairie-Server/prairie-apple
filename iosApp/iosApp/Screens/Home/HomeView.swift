import SwiftUI

extension Notification.Name {
    static let homeSectionsShouldRefresh = Notification.Name("homeSectionsShouldRefresh")
}

/// Main home screen. iOS/macOS render resume-first section rows on a flat
/// background; tvOS uses the Skyline focus marquee (§5.4) — a passive
/// billboard previewing whichever card holds focus.
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
    @State private var currentProfile: UserProfile?
    @State private var homeScrollOffset: CGFloat = 0
    @State private var isRefreshing = false
    @State private var refreshStartedAt: Date?
    @State private var refreshHideTask: Task<Void, Never>?
    private let chromeFadeDistance: CGFloat = 72
    #endif
    @Environment(AppRouter.self) private var router

    var body: some View {
        // On iOS the header floats over the scroll content, which extends
        // behind the status bar with a semi-transparent fill. On tvOS the
        // app-level top bar (owned by `TVMainTabView`) handles profile +
        // utility actions; Home renders the focus marquee over rows, with
        // the backdrop tracking whichever card holds focus (§5.4).
        #if os(tvOS)
        // The shared Skyline feed — the exact same layout component the
        // library Browse tabs use, so Home and the library pages are
        // identical. For You recommendation rows are folded into
        // `displayedSections` right after Continue Watching (§6.1).
        Group {
            if viewModel.sections.isEmpty {
                if let error = viewModel.error {
                    ErrorView(state: error, onRetry: { Task { await viewModel.loadSections() } })
                } else {
                    Color.clear
                }
            } else {
                TVSkylineSectionFeed(
                    sections: displayedSections,
                    focusRequest: homeFocusRequest,
                    isTopMenuFocused: isTopMenuFocused,
                    onTopMenuFocusRequest: onTopMenuFocusRequest,
                    onItemTap: { navigateToDetail($0) }
                )
            }
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
            Color.continuumBackground
                .ignoresSafeArea()

            Group {
                if !displayedSections.isEmpty {
                    scrollContent
                } else if let error = viewModel.error {
                    ErrorView(state: error, onRetry: { Task { await viewModel.loadSections() } })
                } else if viewModel.isLoading {
                    Color.clear
                } else {
                    EmptyStateView(
                        icon: "play.rectangle.on.rectangle",
                        title: "Nothing to watch yet",
                        subtitle: "Add media to your libraries or start watching to see it here."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Content

    #if !os(tvOS)
    private var scrollContent: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: sectionSpacing, pinnedViews: []) {
                    // No hero — reserve runway for the floating Home header so
                    // the first row doesn't slide under the status-bar chrome.
                    Color.clear
                        .frame(height: topRunwaySpacing(topSafeAreaInset: geometry.safeAreaInsets.top))
                        .id(HomeFocusTarget.topSpacer)

                    ForEach(Array(displayedSections.enumerated()), id: \.element.id) { index, section in
                        SectionRow(
                            section: section,
                            onItemTap: { navigateToDetail($0) },
                            prefersDefaultFocusOnFirstItem: index == 0,
                            onMoveUp: index == 0 ? onTopMenuFocusRequest : nil
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
        case topSpacer
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
    private var sectionSpacing: CGFloat {
        ContinuumTheme.largePadding
    }

    private func topRunwaySpacing(topSafeAreaInset: CGFloat) -> CGFloat {
        let headerContentHeight: CGFloat = 40 + (ContinuumTheme.smallPadding * 2)
        return topSafeAreaInset + headerContentHeight + ContinuumTheme.largePadding + ContinuumTheme.smallPadding
    }
    #endif
}
