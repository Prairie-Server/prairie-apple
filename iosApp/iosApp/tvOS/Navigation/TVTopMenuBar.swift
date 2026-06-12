#if os(tvOS)
import SwiftUI

enum TVTopMenuLayout {
    /// Vertical clearance needed when a root tvOS page does not render a
    /// full-bleed hero behind the custom top menu.
    static let contentTopInset: CGFloat = 188
}

/// A library content type that can surface as a root tab (Skyline §3.1).
/// Tabs represent types, not server libraries — a type's tab appears only
/// if the profile can see at least one library of that type.
enum TVLibraryTabType: String, CaseIterable, Hashable {
    case movies
    case series
    case music
    case audiobooks

    var title: String {
        switch self {
        case .movies: return "Movies"
        case .series: return "Series"
        case .music: return "Music"
        case .audiobooks: return "Audiobooks"
        }
    }

    /// Whether a server library belongs under this tab.
    func matches(_ library: Library) -> Bool {
        switch self {
        case .movies: return library.type == "movies"
        case .series: return library.isSeriesLibrary
        case .music: return library.type == "music"
        case .audiobooks: return library.isAudiobookLibrary
        }
    }
}

enum TVRootDestination: Hashable {
    case home
    case libraryType(TVLibraryTabType)
    case calendar

    var title: String {
        switch self {
        case .home: return "Home"
        case .libraryType(let type): return type.title
        case .calendar: return "Calendar"
        }
    }
}

/// Skyline top bar: wordmark left, type-derived tabs centered, search +
/// profile avatar right (§5.1). The bar is custom on purpose — the system
/// `TabView` sidebar steals leftward focus — and draws no background band;
/// it floats over each page's own scrim and dims to 70% while focus is
/// down in the content zone.
struct TVTopMenuBar: View {
    let roots: [TVRootDestination]
    let selectedRoot: TVRootDestination
    let currentProfile: UserProfile?
    /// Whether the signed-in user is a server admin — gates the Admin
    /// Dashboard row in the profile dropdown.
    let isAdmin: Bool
    @Binding var isMenuFocused: Bool
    let isFocusSuppressed: Bool
    let focusRequest: Int
    let onSelectRoot: (TVRootDestination) -> Void
    let onSearch: () -> Void
    let onSwitchProfile: () -> Void
    let onSwitchServer: () -> Void
    let onWatchlist: () -> Void
    let onFavorites: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void
    let onAdminDashboard: () -> Void
    let onSignOut: () -> Void
    var onExit: (() -> Void)? = nil

    @State private var showsProfileActions = false
    @FocusState private var focusedItem: TVTopMenuFocus?

    var body: some View {
        ZStack(alignment: .top) {
            tabCluster

            HStack(spacing: 0) {
                wordmark

                Spacer(minLength: ContinuumTheme.Skyline.tabSpacing)

                trailingCluster
            }
        }
        .frame(height: ContinuumTheme.Skyline.barHeight)
        .padding(.horizontal, ContinuumTheme.Skyline.safeAreaX)
        .padding(.top, ContinuumTheme.Skyline.barTopInset)
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .opacity(isMenuFocused ? 1.0 : ContinuumTheme.Skyline.barDimmedOpacity)
        .animation(.easeInOut(duration: ContinuumTheme.normalDuration), value: isMenuFocused)
        .focusSection()
        .disabled(isFocusSuppressed)
        .modifier(TVTopMenuExitHandler(onExit: onExit))
        .onChange(of: isFocusSuppressed) { _, newValue in
            if newValue {
                focusedItem = nil
            }
        }
        .onChange(of: focusRequest) { _, _ in
            requestMenuFocus()
        }
        .onChange(of: isMenuFocused) { _, newValue in
            if !newValue {
                focusedItem = nil
            }
        }
        .onChange(of: focusedItem) { _, newValue in
            isMenuFocused = newValue != nil
        }
        .fullScreenCover(isPresented: $showsProfileActions) {
            profileMenuPresentation
                .presentationBackground(.clear)
        }
    }

    // MARK: - Clusters

    private var wordmark: some View {
        Text("SILO")
            .font(.system(size: ContinuumTheme.Skyline.wordmarkSize, weight: .heavy))
            .tracking(ContinuumTheme.Skyline.wordmarkTracking)
            .foregroundStyle(.white)
            .accessibilityLabel("Silo")
            .accessibilityHidden(true)
    }

    private var tabCluster: some View {
        HStack(spacing: ContinuumTheme.Skyline.tabSpacing) {
            ForEach(Array(roots.enumerated()), id: \.element) { index, root in
                rootButton(root, index: index, count: roots.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: ContinuumTheme.Skyline.barHeight)
    }

    private var trailingCluster: some View {
        HStack(spacing: ContinuumTheme.Skyline.barTrailingSpacing) {
            searchButton

            profileButton
        }
    }

    // MARK: - Tabs

    private func rootButton(_ root: TVRootDestination, index: Int, count: Int) -> some View {
        let isFocused = focusedItem == .root(root)
        let isSelected = selectedRoot == root

        return Button {
            selectRootFromMenu(root)
        } label: {
            Text(root.title)
                .font(.system(size: ContinuumTheme.Skyline.tabLabelSize, weight: .semibold))
                .foregroundStyle(tabForeground(isSelected: isSelected, isFocused: isFocused))
                .lineLimit(1)
                .padding(.horizontal, ContinuumTheme.Skyline.tabPaddingHorizontal)
                .padding(.vertical, ContinuumTheme.Skyline.tabPaddingVertical)
                .modifier(TVTopMenuCapsuleChrome(isSelected: isSelected, isFocused: isFocused))
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedItem, equals: .root(root))
        .accessibilityLabel("\(root.title), tab, \(index + 1) of \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tabForeground(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused { return .continuumBackground }
        if isSelected { return .white }
        return .white.opacity(0.62)
    }

    private func selectRootFromMenu(_ root: TVRootDestination) {
        onSelectRoot(root)
        DispatchQueue.main.async {
            focusedItem = nil
        }
    }

    private func requestMenuFocus() {
        DispatchQueue.main.async {
            guard !isFocusSuppressed else { return }
            focusedItem = .root(selectedRoot)
        }
    }

    // MARK: - Search

    private var searchButton: some View {
        let isFocused = focusedItem == .search

        return Button(action: onSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isFocused ? Color.continuumBackground : .white.opacity(0.62))
                .frame(
                    width: ContinuumTheme.Skyline.barIconSize,
                    height: ContinuumTheme.Skyline.barIconSize
                )
                .modifier(TVTopMenuCapsuleChrome(isSelected: false, isFocused: isFocused))
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedItem, equals: .search)
        .accessibilityLabel("Search")
    }

    // MARK: - Profile

    private var profileButton: some View {
        let isFocused = focusedItem == .profile

        return Button {
            showsProfileActions = true
        } label: {
            ProfileAvatarView(
                avatar: currentProfile?.avatarEmoji,
                name: currentProfile?.name ?? "",
                size: ContinuumTheme.Skyline.barIconSize,
                backgroundColor: Color.white.opacity(0.18),
                textColor: .white
            )
            .overlay {
                Circle()
                    .strokeBorder(Color.white, lineWidth: isFocused ? 3 : 0)
            }
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedItem, equals: .profile)
        .accessibilityLabel("Profile")
    }

    private var profileMenuPresentation: some View {
        TVProfileDropdown(
            profileName: currentProfile?.name ?? "Profile",
            avatar: currentProfile?.avatarEmoji,
            serverHost: ServerRegistry.shared.activeServer?.displayName,
            isAdmin: isAdmin,
            onSwitchProfile: { dismissProfileMenu(then: onSwitchProfile) },
            onWatchlist: { dismissProfileMenu(then: onWatchlist) },
            onFavorites: { dismissProfileMenu(then: onFavorites) },
            onHistory: { dismissProfileMenu(then: onHistory) },
            onSettings: { dismissProfileMenu(then: onSettings) },
            onAdminDashboard: { dismissProfileMenu(then: onAdminDashboard) },
            onSwitchServer: { dismissProfileMenu(then: onSwitchServer) },
            onSignOut: { dismissProfileMenu(then: onSignOut) },
            onDismiss: { showsProfileActions = false }
        )
    }

    private func dismissProfileMenu(then action: @escaping () -> Void) {
        showsProfileActions = false
        DispatchQueue.main.async {
            action()
        }
    }
}

private enum TVTopMenuFocus: Hashable {
    case root(TVRootDestination)
    case search
    case profile
}

/// Capsule chrome for top-bar tabs and the search button (§5.1):
/// resting = bare label, selected = `chrome.selected` capsule, focused =
/// inverted white capsule. Focus inversion is the platform grammar — no
/// outline ring, no system halo.
private struct TVTopMenuCapsuleChrome: ViewModifier {
    let isSelected: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(fillColor))
            .overlay {
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            }
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var fillColor: Color {
        if isFocused { return .white }
        if isSelected { return .continuumChromeSelectedFill }
        return .clear
    }

    private var borderColor: Color {
        if isFocused { return .clear }
        if isSelected { return .continuumChromeSelectedBorder }
        return .clear
    }
}

private struct TVTopMenuExitHandler: ViewModifier {
    let onExit: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onExit {
            content.onExitCommand(perform: onExit)
        } else {
            content
        }
    }
}

// MARK: - Profile dropdown

private enum TVProfileAction: Hashable {
    case switchProfile
    case watchlist
    case favorites
    case history
    case settings
    case adminDashboard
    case switchServer
    case signOut
}

/// Anchored profile dropdown (§5.8): glass panel under the avatar,
/// right-aligned to `safeArea.x`, over a page scrim. Menu/Back closes.
private struct TVProfileDropdown: View {
    let profileName: String
    let avatar: String?
    /// Display name of the active server, shown under the profile name in
    /// the §5.8 mono header style.
    let serverHost: String?
    let isAdmin: Bool
    let onSwitchProfile: () -> Void
    let onWatchlist: () -> Void
    let onFavorites: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void
    let onAdminDashboard: () -> Void
    let onSwitchServer: () -> Void
    let onSignOut: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedAction: TVProfileAction?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.continuumDropdownScrim
                .ignoresSafeArea()

            panel
                .padding(.trailing, ContinuumTheme.Skyline.safeAreaX)
                .padding(.top, ContinuumTheme.Skyline.dropdownTopInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .ignoresSafeArea()
        .onExitCommand(perform: onDismiss)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            actionButton("Switch Profile", systemImage: "person.2.fill", id: .switchProfile, action: onSwitchProfile)
            actionButton("Watchlist", systemImage: "bookmark.fill", id: .watchlist, action: onWatchlist)
            actionButton("Favorites", systemImage: "heart.fill", id: .favorites, action: onFavorites)
            actionButton("History", systemImage: "clock.fill", id: .history, action: onHistory)

            divider

            actionButton("Settings", systemImage: "gearshape.fill", id: .settings, action: onSettings)
            if isAdmin {
                actionButton("Admin Dashboard", systemImage: "slider.horizontal.3", id: .adminDashboard, action: onAdminDashboard)
            }
            // The guide marks Switch Server as Android-only (§5.8), but tvOS
            // already ships multi-server switching — dropping it here would
            // regress existing users.
            actionButton("Switch Server", systemImage: "server.rack", id: .switchServer, action: onSwitchServer)
            actionButton("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", id: .signOut, isDestructive: true, action: onSignOut)

            divider

            Text("Press Menu to close")
                .font(.system(size: ContinuumTheme.Skyline.dropdownHeaderSize, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.38))
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .padding(ContinuumTheme.Skyline.dropdownPadding)
        .frame(width: ContinuumTheme.Skyline.dropdownWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.Skyline.dropdownCornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.Skyline.dropdownCornerRadius, style: .continuous)
                .fill(Color.continuumGlassStrong)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ContinuumTheme.Skyline.dropdownCornerRadius, style: .continuous)
                .strokeBorder(Color.continuumOutline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 34, y: 18)
        .focusSection()
        .onAppear {
            focusedAction = .switchProfile
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProfileAvatarView(
                avatar: avatar,
                name: profileName,
                size: 44,
                backgroundColor: Color.white.opacity(0.16),
                textColor: .white
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(profileName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let serverHost, !serverHost.isEmpty {
                    Text(serverHost.uppercased())
                        .font(.system(size: ContinuumTheme.Skyline.dropdownHeaderSize, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.38))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.continuumDivider)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        id: TVProfileAction,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 30)

                Text(title)
                    .font(.system(size: ContinuumTheme.Skyline.dropdownRowTextSize, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(TVProfileMenuButtonStyle(isDestructive: isDestructive))
        .focused($focusedAction, equals: id)
    }
}

private struct TVProfileMenuButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        TVProfileMenuButtonBody(
            configuration: configuration,
            isDestructive: isDestructive
        )
    }
}

private struct TVProfileMenuButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isDestructive: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Color.white : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        if isFocused { return .continuumBackground }
        if isDestructive { return .red.opacity(0.9) }
        return .white.opacity(0.86)
    }
}
#endif
