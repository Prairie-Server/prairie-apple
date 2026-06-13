#if os(tvOS)
import SwiftUI

/// Root tvOS shell. Owns a custom Skyline top bar instead of relying on
/// `TabView(.sidebarAdaptable)`, so content can use horizontal remote
/// navigation without the system sidebar claiming leftward focus.
///
/// Tabs are content-type-first (Skyline §3.1): `Home · Movies · Series ·
/// Music · Audiobooks · Calendar`, where each library-type tab appears only
/// if the profile can see at least one library of that type.
struct TVMainTabView: View {
    @Bindable var router: AppRouter
    @State private var selectedRoot: TVRootDestination = .home
    @State private var currentProfile: UserProfile?
    /// Server-side admin flag for the signed-in user; gates the profile
    /// dropdown's Admin Dashboard row.
    @State private var isAdmin = false
    @State private var showServerPicker = false
    @State private var registry = ServerRegistry.shared
    /// Visible libraries for the active profile; drives which type tabs
    /// exist and which library each type tab scopes to.
    @State private var libraries: [Library] = []
    /// Per-type pill selection, session-only (§8): it survives tab
    /// switches but cold start always lands on Browse.
    @State private var pillSelections: [TVLibraryTabType: TVLibraryPill] = [:]
    /// Per-type library scope: which single library each multi-library type
    /// is scoped to (§3.1). Seeded from the persisted choice (or the first
    /// library on cold start) via `TVLibraryScopeStore`, and updated +
    /// re-persisted by the cascade selector. Single-library types resolve
    /// trivially and never need an entry.
    @State private var scopeSelections: [TVLibraryTabType: Int] = [:]
    /// Best-effort library-wide item counts keyed by library id, fetched
    /// lazily (the `Library` model carries none — §G). Feeds the scope
    /// caption and the cascade's per-library count column.
    @State private var libraryItemCounts: [Int: Int] = [:]
    /// The anchored panel currently open from the top bar (cascade or
    /// profile), plus whether focus has descended into it. Owned here so it
    /// renders as a scrimmed overlay over the page (§5.3) — not a pushed
    /// route or full-screen modal.
    @State private var openPanel: TVTopMenuPanel?
    @State private var panelEntersFocus = false
    @State private var panelFocusEntryToken = 0
    @State private var panelHasFocus = false
    /// Bar element to re-focus after Menu-ing out of a panel — its own
    /// anchor, so focus returns to the dwelled tab/avatar (§7).
    @State private var panelReturnFocus: TVTopMenuPanel?
    @State private var isTopMenuFocused = false
    @State private var isTopMenuFocusSuppressed = true
    @State private var topMenuFocusRequest = 0
    /// Active focus hand-down token. Incremented whenever a root is
    /// selected so the freshly-swapped-in content imperatively claims
    /// focus, instead of relying on `prefersDefaultFocus` (which can lose
    /// to geometric proximity, per CLAUDE.md's "tvOS default focus on
    /// d-pad entry"). Starts at 1 so the initial Home content focuses on
    /// first appear.
    @State private var contentFocusRequest = 1
    @Namespace private var tabContentNamespace
    @Environment(AudioPlaybackStore.self) private var audioStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack(path: $router.path) {
                rootContent
                    .navigationDestination(for: Route.self) { route in
                        routeContent(for: route)
                    }
            }

            if router.path.isEmpty {
                TVTopMenuBar(
                    roots: visibleRoots,
                    selectedRoot: selectedRoot,
                    currentProfile: currentProfile,
                    isAdmin: isAdmin,
                    isMenuFocused: $isTopMenuFocused,
                    isFocusSuppressed: isTopMenuFocusSuppressed,
                    focusRequest: topMenuFocusRequest,
                    focusRequestTarget: panelReturnFocus,
                    openPanel: openPanel,
                    panelHasFocus: panelHasFocus,
                    onSelectRoot: selectRoot(_:),
                    onSearch: { router.navigate(to: .search) },
                    onDwell: handleDwell(_:),
                    onEnterPanel: enterOpenPanel,
                    onProfilePressed: openProfilePanelImmediately,
                    onExit: selectedRoot == .home ? nil : returnToHomeInMenu
                )
            }
        }
        // The anchored cascade / profile panel renders here (not as a ZStack
        // sibling) so its `overlayPreferenceValue` can see the bar's
        // published anchors and position the panel under the right element.
        .overlayPreferenceValue(TVTopMenuAnchorKey.self) { anchors in
            panelOverlay(anchors: anchors)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
        .tint(.continuumOnSurface)
        .fullScreenCover(isPresented: Binding(
            get: { audioStore.isShowingFullPlayer },
            set: { if !$0 { audioStore.dismissFullPlayer() } }
        )) {
            AudioFullPlayerView()
        }
        .confirmationDialog(
            "Switch Server",
            isPresented: $showServerPicker,
            titleVisibility: .visible
        ) {
            ForEach(registry.sortedEntries) { entry in
                Button(serverButtonLabel(entry)) {
                    switchToServer(entry)
                }
            }
            Button("Add Server…") {
                router.navigate(to: .serverSetup)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a saved server to switch to.")
        }
        // Outside the presentation modifiers so presented covers (audio
        // player) inherit the router — ErrorView requires it and traps
        // when it's absent.
        .environment(router)
        .task {
            async let profileTask: Void = loadCurrentProfile()
            async let librariesTask: Void = loadLibraries()
            async let adminTask: Void = loadAdminFlag()
            _ = await (profileTask, librariesTask, adminTask)
        }
    }

    private var rootContent: some View {
        ZStack(alignment: .top) {
            Color.continuumBackground
                .ignoresSafeArea()

            selectedRootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // §4.2 tab content switch: an explicit 200 ms opacity
                // crossfade keyed on the selected root, so the incoming page
                // fades in and the outgoing one fades out in place (it never
                // slides). The crossfade animation is supplied by `selectRoot`;
                // Reduce Motion snaps via the `.identity` transition.
                .id(selectedRoot)
                .transition(reduceMotion ? .identity : .opacity)
                .focusScope(tabContentNamespace)
                // While a panel is open the page is scrimmed and inert, so
                // its cards must not be focusable: otherwise d-pad down from
                // a dwell-open tab would jump to a card beneath the scrim
                // instead of firing the tab's `onMoveCommand(.down)` to
                // enter the panel. Re-enables the instant the panel closes.
                .disabled(openPanel != nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .onExitCommand {
            focusTopMenuIfVisible()
        }
    }

    @ViewBuilder
    private var selectedRootContent: some View {
        switch selectedRoot {
        case .home:
            HomeView(
                homeFocusRequest: contentFocusRequest,
                isTopMenuFocused: isTopMenuFocused,
                onTopMenuFocusRequest: { focusTopMenuIfVisible() }
            )
        case .libraryType(let type):
            let active = activeLibrary(for: type)
            TVLibraryTypeTabView(
                type: type,
                libraries: libraries(of: type),
                activeLibrary: active,
                selectedPill: pillSelection(for: type),
                scopeItemCount: active.flatMap { libraryItemCounts[$0.id] },
                focusRequest: contentFocusRequest,
                isTopMenuFocused: isTopMenuFocused,
                onTopMenuFocusRequest: { focusTopMenuIfVisible() }
            )
            // Re-create the tab body when the type changes so per-type
            // section fetches reset cleanly (pill selection survives in
            // pillSelections).
            .id(type)
        case .calendar:
            CalendarView(
                focusRequest: contentFocusRequest,
                onTopMenuFocusRequest: { focusTopMenuIfVisible() }
            )
        }
    }

    // MARK: - Anchored panel overlay (§5.3 / §5.8)

    /// The cascade selector or profile menu, rendered as a scrimmed overlay
    /// anchored under its bar element. This is the whole point of Skyline:
    /// scope/profile changes happen in an anchored dropdown over the page,
    /// never a full-screen takeover, and inside the single shared
    /// `NavigationStack`.
    ///
    /// The bar publishes each panel-bearing element's bounds via
    /// `TVTopMenuAnchorKey`; this overlay resolves the open panel's anchor
    /// with the geometry proxy and positions the panel under it (§5.3
    /// "centered under the tab"; §5.8 "under the avatar", right-aligned).
    @ViewBuilder
    private func panelOverlay(anchors: [TVTopMenuPanel: Anchor<CGRect>]) -> some View {
        if router.path.isEmpty, let panel = openPanel {
            GeometryReader { proxy in
                let leading = panelLeadingInset(
                    panel: panel,
                    anchors: anchors,
                    proxy: proxy
                )

                ZStack(alignment: .topLeading) {
                    // Page scrim (§4.2). tvOS has no pointer, so the panel
                    // closes via Menu/Back (`onExitCommand` below) or by
                    // moving focus off the bar — not a tap.
                    Color.continuumDropdownScrim
                        .ignoresSafeArea()

                    panelBody(for: panel)
                        .modifier(TVPanelOpenTransition(
                            anchorX: panelTransitionAnchorX(panel: panel, anchors: anchors, proxy: proxy, leading: leading),
                            reduceMotion: reduceMotion
                        ))
                        .padding(.leading, leading)
                        .padding(.top, ContinuumTheme.Skyline.dropdownTopInset)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .onExitCommand { closePanel() }
        }
    }

    /// Leading inset that places the panel under its anchor. Library
    /// cascades center their level-1 column (width 460) under the tab;
    /// the profile panel right-aligns to `safeArea.x`. Both clamp inside the
    /// safe area so nothing clips.
    private func panelLeadingInset(
        panel: TVTopMenuPanel,
        anchors: [TVTopMenuPanel: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> CGFloat {
        let safe = ContinuumTheme.Skyline.safeAreaX
        let level1Width = ContinuumTheme.Skyline.dropdownWidth
        let screenWidth = proxy.size.width

        switch panel {
        case .profile:
            // Right-aligned to safeArea.x (§5.8).
            return max(safe, screenWidth - safe - level1Width)
        case .root:
            guard let anchor = anchors[panel] else {
                // Anchor not published yet — fall back to the safe-area edge.
                return safe
            }
            let rect = proxy[anchor]
            let centered = rect.midX - level1Width / 2
            // The two-level cascade extends level1 + gap + flyout to the
            // right; keep the whole thing on screen while preferring to
            // center level-1 under the tab.
            let totalWidth = level1Width
                + ContinuumTheme.Skyline.flyoutGap
                + ContinuumTheme.Skyline.flyoutWidth
            let maxLeading = max(safe, screenWidth - safe - totalWidth)
            return min(max(centered, safe), maxLeading)
        }
    }

    /// Horizontal origin (0…1) for the open scale animation, so the panel
    /// scales up from under its anchor rather than from its own center.
    private func panelTransitionAnchorX(
        panel: TVTopMenuPanel,
        anchors: [TVTopMenuPanel: Anchor<CGRect>],
        proxy: GeometryProxy,
        leading: CGFloat
    ) -> CGFloat {
        guard let anchor = anchors[panel] else { return 0.5 }
        let rect = proxy[anchor]
        let level1Width = ContinuumTheme.Skyline.dropdownWidth
        let originInPanel = rect.midX - leading
        return min(max(originInPanel / level1Width, 0), 1)
    }

    @ViewBuilder
    private func panelBody(for panel: TVTopMenuPanel) -> some View {
        switch panel {
        case .root(let root):
            if case .libraryType(let type) = root {
                cascadePanel(for: type)
            }
        case .profile:
            profilePanel
        }
    }

    private func cascadePanel(for type: TVLibraryTabType) -> some View {
        TVCascadeSelector(
            type: type,
            libraries: libraries(of: type),
            currentScopeId: activeLibrary(for: type)?.id,
            counts: libraryItemCounts,
            entersPanel: panelEntersFocus,
            focusEntryToken: panelFocusEntryToken,
            onCommitLibrary: { commitScope(type: type, library: $0, pill: nil) },
            onCommitSection: { commitScope(type: type, library: $0, pill: $1) },
            onClose: { closePanel() },
            onPanelFocusChanged: { panelHasFocus = $0 }
        )
    }

    private var profilePanel: some View {
        TVProfileDropdown(
            profileName: currentProfile?.name ?? "Profile",
            avatar: currentProfile?.avatarEmoji,
            serverHost: ServerRegistry.shared.activeServer?.displayName,
            isAdmin: isAdmin,
            entersPanel: panelEntersFocus,
            focusEntryToken: panelFocusEntryToken,
            onPanelFocusChanged: { panelHasFocus = $0 },
            onSwitchProfile: { closePanel(then: switchProfile) },
            onWatchlist: { closePanel(then: { router.navigate(to: .watchlist) }) },
            onFavorites: { closePanel(then: { router.navigate(to: .favorites) }) },
            onHistory: { closePanel(then: { router.navigate(to: .history) }) },
            onSettings: { closePanel(then: { router.navigate(to: .settings) }) },
            onAdminDashboard: { closePanel(then: { router.navigate(to: .admin) }) },
            onSwitchServer: { closePanel(then: { showServerPicker = true }) },
            onSignOut: { closePanel(then: { router.signOutAndReset() }) }
        )
    }

    // MARK: - Panel control (§5.3 / §5.8)

    /// Open (or switch) the anchored panel after a bar element's dwell, or
    /// close it when the bar reports focus left every dwellable element.
    /// Focus stays on the bar element until `enterOpenPanel` — opening only
    /// reveals the panel + scrim (§5.3).
    private func handleDwell(_ panel: TVTopMenuPanel?) {
        guard let panel else {
            closePanel()
            return
        }
        guard panel != openPanel else { return }

        // Switching panels (sideways across the bar) re-arms focus-on-the-bar
        // for the new one. Prefetch counts for a cascade so the count column
        // and caption have data by the time the user rolls the list.
        withAnimation(reduceMotion ? nil : .easeOut(duration: ContinuumTheme.Skyline.cascadeScrimDuration)) {
            openPanel = panel
        }
        panelEntersFocus = false
        panelHasFocus = false
        if case .root(.libraryType(let type)) = panel {
            Task { await loadItemCounts(for: type) }
        }
    }

    /// A deliberate **press** on the avatar (§5.8) opens the profile menu
    /// *and* moves focus straight into it — unlike dwell, which reveals the
    /// panel but leaves focus on the avatar until d-pad down. This matches
    /// the prior press-to-open behavior so the menu is immediately usable.
    private func openProfilePanelImmediately() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: ContinuumTheme.Skyline.cascadeScrimDuration)) {
            openPanel = .profile
        }
        // Reset entry state in case a cascade panel was open and focused —
        // the fresh profile panel must hand focus in cleanly via the async
        // enter below, not inherit the prior panel's entered state.
        panelEntersFocus = false
        panelHasFocus = false
        // Hand focus in on the next runloop so the panel has mounted and
        // enabled its rows before the imperative `@FocusState` claim lands.
        DispatchQueue.main.async {
            guard openPanel == .profile else { return }
            enterOpenPanel()
        }
    }

    /// D-pad down on the dwell-open element: hand focus into the panel
    /// (§5.3). Enabling + bumping the entry token makes the panel claim a
    /// row via its own `@FocusState`, which moves system focus off the bar
    /// tab (nulling the bar's focus) without a manual relinquish — avoiding
    /// the race where forcing the bar's focus off would close the panel as
    /// it opens. The tab drops to its selected look via `panelHasFocus`.
    private func enterOpenPanel() {
        guard openPanel != nil else { return }
        panelEntersFocus = true
        panelHasFocus = true
        panelFocusEntryToken += 1
    }

    /// Close the panel without changing scope (Menu/Back, scrim tap, or
    /// focus leaving the bar), optionally running a follow-up action (a
    /// profile-row selection navigates after the panel tears down).
    private func closePanel(then action: (() -> Void)? = nil) {
        guard let panel = openPanel else {
            action?()
            return
        }
        let wasFocused = panelHasFocus
        withAnimation(reduceMotion ? nil : .easeOut(duration: ContinuumTheme.Skyline.cascadeScrimDuration)) {
            openPanel = nil
        }
        panelEntersFocus = false
        panelHasFocus = false

        // Returning focus to *that panel's* tab/avatar (§7) keeps the remote
        // from stranding. Do it whether or not a follow-up action runs:
        // route-pushing actions tear the bar down (the request is a no-op),
        // but `Switch Server` opens a confirmation dialog and leaves the bar
        // on screen — without re-arming, focus would be lost after dismiss.
        // Re-arm before the action so a route push still wins the focus.
        if wasFocused {
            focusTopMenuIfVisible(focusing: panel)
        }
        action?()
    }

    /// Commit a cascade selection (§5.3, §F): set + persist the tab scope,
    /// preselect the pill (Browse for a library-row press; the chosen
    /// section for a flyout-row press), select the tab, and tear the panel
    /// down. The page swaps in place via the scope/pill change + the
    /// existing `.id(activeLibrary.id)` crossfade.
    private func commitScope(type: TVLibraryTabType, library: Library, pill: TVLibraryPill?) {
        scopeSelections[type] = library.id
        TVLibraryScopeStore.shared.setSelectedLibraryId(library.id, for: type)
        pillSelections[type] = pill ?? .browse

        // Tear down the panel first, then select the tab + hand focus to the
        // swapped-in content. Selecting the root bumps contentFocusRequest,
        // which the new page consumes as its entry token.
        withAnimation(reduceMotion ? nil : .easeOut(duration: ContinuumTheme.Skyline.cascadeScrimDuration)) {
            openPanel = nil
        }
        panelEntersFocus = false
        panelHasFocus = false
        selectRoot(.libraryType(type))
    }

    /// Best-effort library-wide item counts for the scope caption (§G) and
    /// the cascade's count column. The `Library` model carries no count, so
    /// this reads `CatalogResponse.total` with a 1-item probe per library.
    /// Failures leave the count absent (the caption omits it — never
    /// fabricated).
    private func loadItemCounts(for type: TVLibraryTabType) async {
        for library in libraries(of: type) where libraryItemCounts[library.id] == nil {
            let query: [String: String] = [
                "source": "query",
                "library_id": String(library.id),
                "offset": "0",
                "limit": "1",
            ]
            guard let response = try? await ContinuumAPI.shared.catalog(query: query),
                  let total = response.total else { continue }
            libraryItemCounts[library.id] = total
        }
    }

    // MARK: - Tab derivation

    /// Fixed root order (Skyline §3.1): Home, then one tab per library
    /// type the profile can see, then Calendar.
    private var visibleRoots: [TVRootDestination] {
        var roots: [TVRootDestination] = [.home]
        for type in TVLibraryTabType.allCases
        where libraries.contains(where: { type.matches($0) }) {
            roots.append(.libraryType(type))
        }
        roots.append(.calendar)
        return roots
    }

    private func libraries(of type: TVLibraryTabType) -> [Library] {
        libraries
            .filter { type.matches($0) }
            .sorted {
                ($0.sortOrder ?? Int.max, $0.id) < ($1.sortOrder ?? Int.max, $1.id)
            }
    }

    /// The library a type tab is currently scoped to (§3.1): the in-session
    /// selection if it still exists, else the persisted choice, else the
    /// first library by sort order (cold start). Returns `nil` only when the
    /// type has no visible libraries.
    private func activeLibrary(for type: TVLibraryTabType) -> Library? {
        let available = libraries(of: type)
        if let selectedId = scopeSelections[type],
           let match = available.first(where: { $0.id == selectedId }) {
            return match
        }
        return TVLibraryScopeStore.shared.resolvedLibrary(for: type, in: available)
    }

    private func pillSelection(for type: TVLibraryTabType) -> Binding<TVLibraryPill> {
        Binding(
            get: { pillSelections[type] ?? .browse },
            set: { pillSelections[type] = $0 }
        )
    }

    private func loadLibraries() async {
        if libraries.isEmpty,
           let cached: LibrariesResponse = ResponseCache.shared.get(CacheKey.userLibraries) {
            libraries = cached.libraries
        }

        do {
            let response: LibrariesResponse = try await ContinuumAPI.shared.get("/api/v1/user/libraries")
            ResponseCache.shared.set(response, for: CacheKey.userLibraries)
            libraries = response.libraries
            ensureSelectedRootIsVisible()
        } catch {
            // Keep whatever tabs we already have (cached or none) — Home
            // and Calendar always stay reachable, so a transient failure
            // never strands the user.
        }
    }

    /// A library refresh can remove the type the user is parked on (e.g.
    /// profile permissions changed). Snap back to Home rather than leaving
    /// a tab-less content view on screen.
    private func ensureSelectedRootIsVisible() {
        guard case .libraryType(let type) = selectedRoot else { return }
        if !libraries.contains(where: { type.matches($0) }) {
            selectedRoot = .home
            contentFocusRequest += 1
        }
    }

    // MARK: - Root selection & focus

    private func selectRoot(_ root: TVRootDestination) {
        router.popToRoot()

        suppressTopMenuFocusForContentHandoff()
        // Tab content switches crossfade over 200 ms (§4.2); the outgoing
        // view never owns focus here because selection happens from the bar.
        // Reduce Motion snaps (the `.identity` transition + nil animation).
        withAnimation(reduceMotion ? nil : .easeInOut(duration: ContinuumTheme.normalDuration)) {
            selectedRoot = root
        }
        // Push focus into whichever root content is swapping in. Suppressing
        // the menu relinquishes its focus (TVTopMenuBar.onChange(isFocusSuppressed)),
        // so without an active hand-down the new content never claims focus and
        // the remote goes dead until the user blindly swipes.
        contentFocusRequest += 1
    }

    /// Re-arm the top bar's focus. `focusing` overrides which element the
    /// bar lands on (used by panel-close to return to the panel's anchor,
    /// §7); the default `nil` falls back to the selected tab. Always written
    /// so a prior override can't leak into a later content-exit call.
    private func focusTopMenuIfVisible(focusing target: TVTopMenuPanel? = nil) {
        // The custom top menu only exists on root pages. Pushed detail,
        // player, and settings routes should keep normal navigation-stack
        // back behavior instead of being intercepted by the root shell.
        guard router.path.isEmpty else { return }

        panelReturnFocus = target
        guard !isTopMenuFocused else { return }

        withAnimation(reduceMotion ? nil : ContinuumTheme.springAnimation) {
            isTopMenuFocusSuppressed = false
            topMenuFocusRequest += 1
        }
    }

    private func returnToHomeInMenu() {
        selectedRoot = .home
        panelReturnFocus = nil
        withAnimation(reduceMotion ? nil : ContinuumTheme.springAnimation) {
            // Un-suppress before requesting focus: requestMenuFocus drops the
            // request while the menu is suppressed, which could leave the
            // Home button unfocused after the exit-to-home gesture.
            isTopMenuFocusSuppressed = false
            topMenuFocusRequest += 1
        }
    }

    private func suppressTopMenuFocusForContentHandoff() {
        isTopMenuFocused = false
        isTopMenuFocusSuppressed = true
    }

    private func switchProfile() {
        AuthService.shared.profileId = nil
        router.showProfileSelection()
    }

    private func loadCurrentProfile() async {
        guard let profileId = AuthService.shared.profileId else {
            currentProfile = nil
            return
        }

        do {
            let profiles = try await AuthService.shared.getProfiles()
            currentProfile = profiles.first(where: { $0.id == profileId })
        } catch {
            currentProfile = nil
        }
    }

    private func loadAdminFlag() async {
        let user: UserInfo? = try? await ContinuumAPI.shared.get("/api/v1/user/me")
        isAdmin = user?.isAdmin == true
    }

    private func serverButtonLabel(_ entry: ServerEntry) -> String {
        entry.id == registry.activeServerId
            ? "\(entry.displayName) (Current)"
            : entry.displayName
    }

    /// Switch to the selected server and snap the auth state machine to
    /// the right screen (login / profile select / home) based on what's
    /// remembered for that server.
    private func switchToServer(_ entry: ServerEntry) {
        guard entry.id != registry.activeServerId else { return }
        Task {
            await registry.switchTo(serverId: entry.id)
            await MainActor.run {
                selectedRoot = .home
                currentProfile = nil
                libraries = []
                pillSelections = [:]
                isAdmin = false
                refreshAuthState()
            }
            if AuthService.shared.hasProfile {
                async let profileTask: Void = loadCurrentProfile()
                async let librariesTask: Void = loadLibraries()
                async let adminTask: Void = loadAdminFlag()
                _ = await (profileTask, librariesTask, adminTask)
            }
        }
    }

    private func refreshAuthState() {
        router.popToRoot()
        let auth = AuthService.shared
        if !auth.hasServer {
            router.authState = .needsServerSetup
        } else if !auth.isLoggedIn {
            router.authState = .needsLogin
        } else if !auth.hasProfile {
            router.authState = .needsProfile
        } else {
            router.authState = .authenticated
        }
    }

    @ViewBuilder
    private func routeContent(for route: Route) -> some View {
        switch route {
        case .library(let libraryId, let title):
            LibraryDetailView(libraryId: libraryId, initialTitle: title)
        case .libraryCollection(let libraryId, let collectionId, let title, let kind):
            LibraryCollectionDetailView(
                libraryId: libraryId,
                collectionId: collectionId,
                title: title,
                kind: kind
            )
        case .itemDetail(let contentId):
            ItemDetailView(contentId: contentId)
        case .personDetail(let personId):
            PersonDetailView(personId: personId)
        case .player(let contentId, let startFromBeginning, let resumePosition):
            PlayerView(
                contentId: contentId,
                startFromBeginning: startFromBeginning,
                resumePositionOverride: resumePosition
            )
        case .playerWithFile(let contentId, let fileId, let audioTrackIndex, let subtitleTrackIndex, let startFromBeginning, let resumePosition):
            PlayerView(
                contentId: contentId,
                preferredFileId: fileId,
                preferredAudioTrackIndex: audioTrackIndex,
                preferredSubtitleTrackIndex: subtitleTrackIndex,
                startFromBeginning: startFromBeginning,
                resumePositionOverride: resumePosition
            )
        case .favorites:
            FavoritesView()
        case .watchlist:
            WatchlistView()
        case .history:
            HistoryView()
        case .collections:
            CollectionsView()
        case .collectionDetail(let id):
            CollectionDetailView(collectionId: id)
        case .browse(let libraryId):
            BrowseView(libraryId: libraryId)
        case .admin:
            AdminDashboardView()
        case .search:
            SearchView(usesTVTopMenuInset: false)
        case .settings:
            TVSettingsView()
        case .recommendations:
            RecommendationsView()
        case .serverList:
            ServerListView()
        case .serverSetup:
            // Pushed from the profile menu's "Add Server…" button — staying
            // on the nav stack means the tvOS back button returns to the
            // previous active server instead of dropping the authenticated
            // tree entirely. Successful `connect()` flips authState to
            // `.needsLogin` and replaces this view tree.
            TVServerSetupView(router: router)
        case .tvLibraryGrid(let libraryId, let libraryName, let libraryType, let payload, let subtitle):
            TVLibraryGridView(
                libraryId: libraryId,
                libraryName: libraryName,
                libraryType: libraryType,
                initialFilter: TVLibraryFilter(
                    namePrefix: payload.namePrefix,
                    genre: payload.genre,
                    yearMin: payload.yearMin,
                    yearMax: payload.yearMax,
                    sort: payload.sort
                ),
                subtitle: subtitle
            )
        default:
            EmptyStateView(icon: "questionmark.circle", title: "Unknown", subtitle: nil)
                .continuumBackground()
        }
    }
}

// MARK: - Panel open transition

/// Cascade / profile open animation (§4.2): 180 ms scale 0.96 → 1.0 + fade,
/// scaling up from under the anchor (`anchorX`) so the panel grows out of
/// its tab rather than its own center. Reduce Motion snaps with no scale or
/// fade.
private struct TVPanelOpenTransition: ViewModifier {
    let anchorX: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(.identity)
        } else {
            content.transition(
                .scale(scale: ContinuumTheme.Skyline.cascadeOpenScale, anchor: UnitPoint(x: anchorX, y: 0))
                    .combined(with: .opacity)
                    .animation(.easeOut(duration: ContinuumTheme.Skyline.cascadeOpenDuration))
            )
        }
    }
}
#endif
