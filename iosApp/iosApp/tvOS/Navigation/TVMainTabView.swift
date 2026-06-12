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
    @State private var showServerPicker = false
    @State private var registry = ServerRegistry.shared
    /// Visible libraries for the active profile; drives which type tabs
    /// exist and which library each type tab scopes to.
    @State private var libraries: [Library] = []
    /// Per-type pill selection, session-only (§8): it survives tab
    /// switches but cold start always lands on Featured.
    @State private var pillSelections: [TVLibraryTabType: TVLibraryPill] = [:]
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
                    isMenuFocused: $isTopMenuFocused,
                    isFocusSuppressed: isTopMenuFocusSuppressed,
                    focusRequest: topMenuFocusRequest,
                    onSelectRoot: selectRoot(_:),
                    onSearch: { router.navigate(to: .search) },
                    onSwitchProfile: switchProfile,
                    onSwitchServer: { showServerPicker = true },
                    onSettings: { router.navigate(to: .settings) },
                    onSignOut: { router.signOutAndReset() },
                    onExit: selectedRoot == .home ? nil : returnToHomeInMenu
                )
            }
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
            _ = await (profileTask, librariesTask)
        }
    }

    private var rootContent: some View {
        ZStack(alignment: .top) {
            Color.continuumBackground
                .ignoresSafeArea()

            selectedRootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusScope(tabContentNamespace)
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
                onTopMenuFocusRequest: focusTopMenuIfVisible
            )
        case .libraryType(let type):
            TVLibraryTypeTabView(
                type: type,
                libraries: libraries(of: type),
                selectedPill: pillSelection(for: type),
                focusRequest: contentFocusRequest,
                isTopMenuFocused: isTopMenuFocused,
                onTopMenuFocusRequest: focusTopMenuIfVisible
            )
            // Re-create the tab body when the type changes so per-type
            // section fetches reset cleanly (pill selection survives in
            // pillSelections).
            .id(type)
        case .calendar:
            CalendarView(
                focusRequest: contentFocusRequest,
                onTopMenuFocusRequest: focusTopMenuIfVisible
            )
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

    private func pillSelection(for type: TVLibraryTabType) -> Binding<TVLibraryPill> {
        Binding(
            get: { pillSelections[type] ?? .featured },
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
        withAnimation(.easeInOut(duration: ContinuumTheme.normalDuration)) {
            // Tab content switches crossfade (§4.2); the outgoing view never
            // owns focus here because selection happens from the bar.
            selectedRoot = root
        }
        // Push focus into whichever root content is swapping in. Suppressing
        // the menu relinquishes its focus (TVTopMenuBar.onChange(isFocusSuppressed)),
        // so without an active hand-down the new content never claims focus and
        // the remote goes dead until the user blindly swipes.
        contentFocusRequest += 1
    }

    private func focusTopMenuIfVisible() {
        // The custom top menu only exists on root pages. Pushed detail,
        // player, and settings routes should keep normal navigation-stack
        // back behavior instead of being intercepted by the root shell.
        guard router.path.isEmpty else { return }
        guard !isTopMenuFocused else { return }

        withAnimation(ContinuumTheme.springAnimation) {
            isTopMenuFocusSuppressed = false
            topMenuFocusRequest += 1
        }
    }

    private func returnToHomeInMenu() {
        selectedRoot = .home
        withAnimation(ContinuumTheme.springAnimation) {
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
                refreshAuthState()
            }
            if AuthService.shared.hasProfile {
                async let profileTask: Void = loadCurrentProfile()
                async let librariesTask: Void = loadLibraries()
                _ = await (profileTask, librariesTask)
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
#endif
