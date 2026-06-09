#if os(tvOS)
import SwiftUI

/// Root tvOS shell. Owns a custom Netflix-style top menu instead of relying on
/// `TabView(.sidebarAdaptable)`, so content can use horizontal remote
/// navigation without the system sidebar claiming leftward focus.
struct TVMainTabView: View {
    @Bindable var router: AppRouter
    @State private var selectedRoot: TVRootDestination = .home
    @State private var currentProfile: UserProfile?
    @State private var showServerPicker = false
    @State private var registry = ServerRegistry.shared
    @State private var libraryMode: TVLibraryLandingMode = .recommended
    @State private var libraryHeaderContext: TVLibraryHeaderContext?
    @State private var librarySelectionRequest: TVLibrarySelectionRequest?
    @State private var librarySelectionRequestToken = 0
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
                    selectedRoot: selectedRoot,
                    currentProfile: currentProfile,
                    libraryHeaderContext: libraryHeaderContext,
                    libraryMode: libraryMode,
                    isMenuFocused: $isTopMenuFocused,
                    isFocusSuppressed: isTopMenuFocusSuppressed,
                    focusRequest: topMenuFocusRequest,
                    onSelectRoot: selectRoot(_:),
                    onSelectLibraryMode: selectLibraryMode(_:),
                    onSelectLibrary: requestLibrarySelection(_:),
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
            await loadCurrentProfile()
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
        case .search:
            SearchView()
        case .libraries:
            TVLibrariesTabView(
                selectedMode: $libraryMode,
                headerContext: $libraryHeaderContext,
                librarySelectionRequest: librarySelectionRequest,
                focusRequest: contentFocusRequest,
                isTopMenuFocused: isTopMenuFocused,
                onTopMenuFocusRequest: focusTopMenuIfVisible
            )
        case .forYou:
            RecommendationsView(
                focusRequest: contentFocusRequest,
                onTopMenuFocusRequest: focusTopMenuIfVisible
            )
        }
    }

    private func selectRoot(_ root: TVRootDestination) {
        router.popToRoot()
        if root == .search {
            router.navigate(to: .search)
            return
        }

        suppressTopMenuFocusForContentHandoff()
        selectedRoot = root
        // Push focus into whichever root content is swapping in. Suppressing
        // the menu relinquishes its focus (TVTopMenuBar.onChange(isFocusSuppressed)),
        // so without an active hand-down the new content never claims focus and
        // the remote goes dead until the user blindly swipes. Home always had
        // this; Libraries and For You now share it.
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

    private func selectLibraryMode(_ mode: TVLibraryLandingMode) {
        withAnimation(ContinuumTheme.springAnimation) {
            libraryMode = mode
        }
    }

    private func requestLibrarySelection(_ libraryID: Int) {
        librarySelectionRequestToken += 1
        librarySelectionRequest = TVLibrarySelectionRequest(
            libraryID: libraryID,
            token: librarySelectionRequestToken
        )
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
                refreshAuthState()
            }
            if AuthService.shared.hasProfile {
                await loadCurrentProfile()
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
            // Pushed from the sidebar server switcher's "Add Server…"
            // button — staying on the nav stack means the tvOS back button
            // returns to the previous active server instead of dropping
            // the authenticated tree entirely. Successful `connect()` flips
            // authState to `.needsLogin` and replaces this view tree.
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
