import SwiftUI

/// Root of the Libraries tab.
///
/// Mirrors the Plex/Android flow: the tab lands directly on the active
/// library's 3-tab view (Recommended / Library / Collections) with a custom
/// top bar — library selector on the left, search/saved/profile actions
/// on the right.
struct LibrariesTabView: View {
    @State private var libraries: [Library] = []
    @State private var selectedLibraryId: Int?
    @State private var selectedTab: LibraryPageTab = .recommended
    @State private var isLoading = true
    @State private var error: ErrorState?
    @State private var showPicker = false
    @State private var currentProfile: UserProfile?
    /// How far the Recommended tab has been scrolled from the top (in pt).
    /// Drives the fade-in of the chrome scrim so the header is fully
    /// transparent while the hero is at rest, then matches the current
    /// gradient once the user scrolls past the hero's top edge.
    @State private var recommendedScrollOffset: CGFloat = 0

    /// Distance (pt) over which the chrome scrim fades in as the user
    /// scrolls away from the resting hero. Chosen to feel responsive without
    /// flickering on tiny rubber-band movements.
    private let chromeScrimFadeDistance: CGFloat = 80

    /// Persist the last-selected library across launches so the user lands
    /// back where they left off. Stored as Int because `@AppStorage` does
    /// not support `Int?` directly; `0` represents "no stored value".
    @AppStorage("librariesTabSelectedLibraryId") private var storedLibraryId: Int = 0

    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let activeLibrary {
                loadedContent(activeLibrary: activeLibrary)
            } else if let error, libraries.isEmpty {
                ErrorView(state: error, onRetry: { Task { await loadLibraries() } })
            } else if isLoading && libraries.isEmpty {
                Color.clear
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "No libraries available",
                    subtitle: "Libraries visible to this profile will appear here."
                )
            }
        }
        .continuumBackground()
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task {
            await loadLibraries()
            await loadCurrentProfile()
        }
        .sheet(isPresented: $showPicker) {
            LibraryPickerSheet(
                libraries: libraries,
                selectedLibraryId: selectedLibraryId,
                onSelect: { id in
                    selectedLibraryId = id
                    storedLibraryId = id
                    showPicker = false
                }
            )
        }
    }

    @ViewBuilder
    private func loadedContent(activeLibrary: Library) -> some View {
        // Switch tab content directly here (rather than going through
        // `LibraryDetailView`) so we can hoist the top bar + tab selector
        // into a single `safeAreaInset` overlay. That lets the Recommended
        // tab's featured carousel ignore the top safe area and render its
        // backdrop all the way up behind the chrome, while Library/
        // Collections keep their normal layout below it.
        tabContent(activeLibrary: activeLibrary)
            // Forces the whole tab subtree to reset when switching
            // libraries, so stale content never flashes on screen.
            .id(activeLibrary.id)
            .safeAreaInset(edge: .top, spacing: 0) {
                topChrome(activeLibrary: activeLibrary)
            }
    }

    @ViewBuilder
    private func tabContent(activeLibrary: Library) -> some View {
        switch selectedTab {
        case .recommended:
            LibraryRecommendedView(
                libraryId: activeLibrary.id,
                extendsBackdropToTop: true,
                onScrollOffsetChange: { recommendedScrollOffset = $0 }
            )
        case .library:
            BrowseView(libraryId: activeLibrary.id, title: nil, showsSearchShortcut: false)
        case .collections:
            LibraryCollectionsView(libraryId: activeLibrary.id)
        }
    }

    /// Opacity applied to the Recommended-tab chrome scrim. 0 while the hero
    /// is at rest (header is fully transparent); climbs linearly to 1 once
    /// the user has scrolled `chromeScrimFadeDistance` past the top.
    private var chromeScrimOpacity: Double {
        guard selectedTab == .recommended else { return 0 }
        let progress = recommendedScrollOffset / chromeScrimFadeDistance
        return min(max(Double(progress), 0), 1)
    }

    @ViewBuilder
    private func topChrome(activeLibrary: Library) -> some View {
        VStack(spacing: 0) {
            LibrariesTopBar(
                activeLibrary: activeLibrary,
                canSwitch: libraries.count > 1,
                profile: currentProfile,
                onLibraryTap: { showPicker = true },
                onSearch: { router.navigate(to: .search) },
                onSwitchProfile: {
                    AuthService.shared.profileId = nil
                    router.showProfileSelection()
                },
                onSwitchServer: { router.navigate(to: .serverList) },
                onSignOut: { router.signOutAndReset() }
            )
            .padding(.horizontal, ContinuumTheme.padding)
            .padding(.top, ContinuumTheme.smallPadding)
            .padding(.bottom, ContinuumTheme.smallPadding)

            LibraryPageTabSelector(selectedTab: $selectedTab)
                .padding(.bottom, ContinuumTheme.padding)
        }
        // On the Recommended tab the chrome sits over the featured carousel
        // backdrop. The scrim is fully transparent while the hero is at
        // rest and fades in as the user scrolls, so the header reads as
        // part of the artwork until movement starts.
        .background {
            if selectedTab == .recommended {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.25),
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .opacity(chromeScrimOpacity)
            }
        }
    }

    private var activeLibrary: Library? {
        libraries.first(where: { $0.id == selectedLibraryId })
    }

    private func loadLibraries() async {
        // Hydrate from cache so a returning visit paints last-known
        // libraries instantly while the refresh runs.
        if libraries.isEmpty,
           let cached: LibrariesResponse = ResponseCache.shared.get("libraries:list") {
            libraries = cached.libraries
            applyLibrarySelection()
        }
        if libraries.isEmpty {
            isLoading = true
        }
        error = nil
        do {
            let response: LibrariesResponse = try await ContinuumAPI.shared.get("/api/v1/user/libraries")
            ResponseCache.shared.set(response, for: "libraries:list")
            libraries = response.libraries
            applyLibrarySelection()
        } catch {
            if libraries.isEmpty {
                self.error = ErrorState(error)
            }
        }
        isLoading = false
    }

    /// Preserve the stored selection if it still exists; otherwise fall
    /// back to the first available library.
    private func applyLibrarySelection() {
        let restored = storedLibraryId != 0
            ? libraries.first(where: { $0.id == storedLibraryId })?.id
            : nil
        let resolved = restored ?? libraries.first?.id
        selectedLibraryId = resolved
        if let resolved { storedLibraryId = resolved }
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
}

// MARK: - Top Bar

/// Plex-style top bar: library selector on the left, shared action icons
/// (search / profile) on the right.
private struct LibrariesTopBar: View {
    let activeLibrary: Library
    let canSwitch: Bool
    let profile: UserProfile?
    let onLibraryTap: () -> Void
    let onSearch: () -> Void
    let onSwitchProfile: () -> Void
    let onSwitchServer: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SidebarToggleButton()

            LibrarySelectorButton(
                library: activeLibrary,
                canSwitch: canSwitch,
                onTap: onLibraryTap
            )

            Spacer(minLength: 8)

            TabTopBarActions(
                profile: profile,
                onSearch: onSearch,
                onSwitchProfile: onSwitchProfile,
                onSwitchServer: onSwitchServer,
                onSignOut: onSignOut
            )
        }
    }
}

/// Compact library selector: library name with a small chevron, stacked above
/// a secondary label. Tap opens the picker sheet.
private struct LibrarySelectorButton: View {
    let library: Library
    let canSwitch: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(library.name)
                        .font(.continuumTitle)
                        .foregroundColor(.continuumOnSurface)
                        .lineLimit(1)
                    if canSwitch {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.continuumOnSurface)
                    }
                }
                Text(typeLabel)
                    .font(.continuumCaption)
                    .foregroundColor(.continuumSecondaryText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSwitch)
    }

    private var typeLabel: String {
        switch library.type {
        case "movies": return "Movies"
        case "series": return "Series"
        default: return "Library"
        }
    }
}

// MARK: - Library Picker Sheet

/// Sheet listing all libraries available to the active profile. Used for
/// switching the active library from the Libraries tab.
private struct LibraryPickerSheet: View {
    let libraries: [Library]
    let selectedLibraryId: Int?
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(tvOS)
        // tvOS does not support medium detents or presentation drags; render
        // as a full-screen focus-friendly list instead.
        content
        #else
        NavigationStack {
            content
                .toolbar {
                    #if os(macOS)
                    ToolbarItem {
                        Button("Done") { dismiss() }
                    }
                    #else
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                    #endif
                }
        }
        #if !os(macOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(libraries) { library in
                    LibraryPickerRow(
                        library: library,
                        isSelected: library.id == selectedLibraryId,
                        onTap: { onSelect(library.id) }
                    )
                }
            }
            .padding(.horizontal, ContinuumTheme.padding)
            .padding(.vertical, ContinuumTheme.padding)
        }
        .continuumBackground()
        .navigationTitle("Libraries")
    }
}

private struct LibraryPickerRow: View {
    let library: Library
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.continuumOnSurface.opacity(0.12))
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.continuumOnSurface)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(library.name)
                        .font(.continuumHeadline)
                        .foregroundColor(.continuumOnSurface)
                    Text(typeLabel)
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.continuumOnSurface)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius)
                    .fill(isSelected ? Color.continuumOnSurface.opacity(0.10) : Color.continuumSurfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: ContinuumTheme.cornerRadius)
                            .stroke(Color.continuumOutline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch library.type {
        case "movies": return "film.fill"
        case "series": return "tv.fill"
        default: return "square.stack.3d.up.fill"
        }
    }

    private var typeLabel: String {
        switch library.type {
        case "movies": return "Movies library"
        case "series": return "TV library"
        default: return "Library"
        }
    }
}
