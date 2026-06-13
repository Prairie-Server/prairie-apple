#if os(tvOS)
import SwiftUI

enum TVTopMenuLayout {
    /// Vertical clearance needed when a root tvOS page does not render a
    /// full-bleed hero behind the custom top menu.
    static let contentTopInset: CGFloat = 188
}

/// Publishes the on-screen bounds of each panel-bearing bar element so the
/// shell can anchor the cascade / profile panel under it (§5.3 "centered
/// under the tab", §5.8 "under the avatar"). One `Anchor` per element; the
/// shell resolves the open panel's anchor in its own coordinate space.
struct TVTopMenuAnchorKey: PreferenceKey {
    static let defaultValue: [TVTopMenuPanel: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TVTopMenuPanel: Anchor<CGRect>],
        nextValue: () -> [TVTopMenuPanel: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
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

    /// SF Symbol for a library row of this type in the cascade level-1
    /// panel (§5.3). Per-library art isn't fetched there — the icon is a
    /// quiet type cue, mirroring the empty-state glyphs elsewhere.
    var systemImage: String {
        switch self {
        case .movies: return "film.stack"
        case .series: return "tv"
        case .music: return "music.note"
        case .audiobooks: return "book.closed"
        }
    }

    /// Mono section header for the cascade level-1 panel (§5.3), e.g.
    /// `MOVIE LIBRARIES`.
    var librariesHeader: String {
        switch self {
        case .movies: return "MOVIE LIBRARIES"
        case .series: return "SERIES LIBRARIES"
        case .music: return "MUSIC LIBRARIES"
        case .audiobooks: return "AUDIOBOOK LIBRARIES"
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
    /// Bar element to focus on the next `focusRequest` bump, overriding the
    /// default of the selected tab. The shell sets this so Menu-ing out of a
    /// panel returns focus to the *panel's* tab/avatar (§7), not whatever
    /// root happens to be selected.
    var focusRequestTarget: TVTopMenuPanel? = nil
    /// Which bar element currently has an anchored panel open (the host
    /// owns the panel; the bar only drives the dwell + hand-off). When set
    /// to the focused element, its capsule drops from inverted to
    /// `chrome.selected` once focus descends into the panel.
    let openPanel: TVTopMenuPanel?
    /// True once focus has descended from the bar into the open panel —
    /// the tab/avatar then reads as selected, not focused (§5.1).
    let panelHasFocus: Bool
    let onSelectRoot: (TVRootDestination) -> Void
    let onSearch: () -> Void
    /// A bar element rested under focus for the dwell interval, or focus
    /// left every dwellable element (`nil` → close any open panel). §5.3.
    let onDwell: (TVTopMenuPanel?) -> Void
    /// D-pad down on a dwell-open element: hand focus into its panel (§5.3).
    let onEnterPanel: () -> Void
    /// Press on the profile avatar — opens the profile panel immediately
    /// (the host treats press and dwell identically for the avatar, §5.8).
    let onProfilePressed: () -> Void
    var onExit: (() -> Void)? = nil

    @FocusState private var focusedItem: TVTopMenuFocus?
    /// Dwell timer keyed on the focused element; cancelled on every focus
    /// move so bar sweeps never open a panel (§5.3, Open-Q5/Q7).
    @State private var dwellTask: Task<Void, Never>?

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
        // Menu while a panel is dwell-open (focus still on the tab/avatar)
        // closes the panel instead of exiting the page — without this, a tab
        // whose page is Home (so `onExit` is nil) would let Menu fall through
        // to the system. Once focus is *inside* the panel, the overlay's own
        // `onExitCommand` catches Menu first, so this only handles the
        // focus-on-bar case.
        .modifier(TVTopMenuExitHandler(onExit: barExitAction))
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
            scheduleDwell(for: newValue)
        }
        .onDisappear { dwellTask?.cancel() }
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
        let hasFocus = focusedItem == .root(root)
        // While its panel owns focus the tab reads as selected, not focused
        // (§5.1) — the inverted look transfers to the panel row.
        let panelOwnsFocus = panelHasFocus && openPanel == .root(root)
        let isFocused = hasFocus && !panelOwnsFocus
        let isSelected = selectedRoot == root || panelOwnsFocus

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
        // Down hands focus into an open cascade panel for this tab (§5.3).
        // Fires only when the engine can't move focus within the bar — i.e.
        // the bar is a single row, so down always reaches here.
        .modifier(TVTopMenuDownHandler(isActive: openPanel == .root(root)) {
            onEnterPanel()
        })
        // Library tabs publish their bounds so the shell can center the
        // cascade panel under them (§5.3); other tabs have no panel.
        .modifier(TVTopMenuAnchorPublisher(panel: libraryRoot(root) != nil ? .root(root) : nil))
        .accessibilityLabel("\(root.title), tab, \(index + 1) of \(count)")
        .accessibilityHint(libraryRoot(root) != nil ? "Rest to choose a library" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func libraryRoot(_ root: TVRootDestination) -> TVLibraryTabType? {
        if case .libraryType(let type) = root { return type }
        return nil
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
            switch focusRequestTarget {
            case .root(let root): focusedItem = .root(root)
            case .profile: focusedItem = .profile
            case .none: focusedItem = .root(selectedRoot)
            }
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
        // The avatar keeps its focus ring while the profile panel is open
        // and focus is still on the avatar; once focus descends into the
        // panel the ring drops (the panel rows carry focus then, §5.8).
        let panelOwnsFocus = panelHasFocus && openPanel == .profile
        let isFocused = focusedItem == .profile && !panelOwnsFocus

        return Button {
            // Press opens immediately (§5.8) — identical outcome to dwell.
            onProfilePressed()
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
        .modifier(TVTopMenuDownHandler(isActive: openPanel == .profile) {
            onEnterPanel()
        })
        .modifier(TVTopMenuAnchorPublisher(panel: .profile))
        .accessibilityLabel("Profile")
        .accessibilityHint("Rest or press to open the profile menu")
    }

    /// Menu handler for the bar: closes a dwell-open panel first (§5.3
    /// "Menu closes"), otherwise the page-level exit (Home / system).
    private var barExitAction: (() -> Void)? {
        if openPanel != nil {
            return { onDwell(nil) }
        }
        return onExit
    }

    // MARK: - Dwell (§5.3, §5.8)

    /// Restart the dwell timer whenever focus settles on a new bar
    /// element. A library tab or the profile avatar opens its panel after
    /// the dwell interval; any other element (or losing focus) closes any
    /// open panel immediately. Cancelled on every focus move so a sweep
    /// across the bar never opens a panel (Open-Q5/Q7).
    private func scheduleDwell(for item: TVTopMenuFocus?) {
        dwellTask?.cancel()

        // Moving focus to a *different bar element* — another tab, or the
        // search button — closes the open panel right away (§5.3: "moving
        // sideways to another tab closes it"), so it doesn't linger during
        // the new element's dwell. Critically, a `nil` item (focus left the
        // bar entirely) does NOT close: on a root page that only happens
        // when the panel claims focus on d-pad down, and closing then would
        // shut the panel the instant focus enters it.
        if let openPanel, let item, !item.matches(panel: openPanel) {
            onDwell(nil)
        }

        guard let target = dwellTarget(for: item) else { return }

        dwellTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: ContinuumTheme.Skyline.cascadeDwellMilliseconds * 1_000_000
            )
            guard !Task.isCancelled else { return }
            // Confirm focus is still on the same element before opening —
            // a late move that didn't cancel in time must not fire.
            guard focusedItem == item else { return }
            onDwell(target)
        }
    }

    /// Maps a focused bar element to the panel it should dwell-open, or
    /// `nil` for elements with no panel (wordmark/search/non-library tabs).
    private func dwellTarget(for item: TVTopMenuFocus?) -> TVTopMenuPanel? {
        switch item {
        case .root(let root):
            guard case .libraryType = root else { return nil }
            return .root(root)
        case .profile:
            return .profile
        case .search, .none:
            return nil
        }
    }
}

/// Which bar element an anchored panel is attached to (§5.3/§5.8).
enum TVTopMenuPanel: Hashable {
    case root(TVRootDestination)
    case profile
}

private enum TVTopMenuFocus: Hashable {
    case root(TVRootDestination)
    case search
    case profile

    /// Whether this focused element is the anchor of the given open panel —
    /// i.e. focus is still "on" that panel's tab/avatar, not a sibling.
    func matches(panel: TVTopMenuPanel) -> Bool {
        switch (self, panel) {
        case let (.root(a), .root(b)): return a == b
        case (.profile, .profile): return true
        default: return false
        }
    }
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

/// Hands d-pad **down** on a dwell-open bar element into its panel (§5.3).
/// The handler is attached only while a panel is open for the element so a
/// normal down-press (no panel) still falls through to the page's content
/// zone via the shell's existing focus hand-down.
private struct TVTopMenuDownHandler: ViewModifier {
    let isActive: Bool
    let onDown: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.onMoveCommand { direction in
                if direction == .down { onDown() }
            }
        } else {
            content
        }
    }
}

/// Publishes a bar element's bounds into `TVTopMenuAnchorKey` so the shell
/// can anchor its panel. A `nil` panel publishes nothing (elements with no
/// panel).
private struct TVTopMenuAnchorPublisher: ViewModifier {
    let panel: TVTopMenuPanel?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let panel {
            content.anchorPreference(key: TVTopMenuAnchorKey.self, value: .bounds) {
                [panel: $0]
            }
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

/// Anchored profile dropdown panel (§5.8): the same `glass.strong` level-1
/// panel as the cascade, hosted by the shell under the avatar. The shell
/// owns the scrim and Menu-to-close; this view owns only its rows and the
/// dwell focus hand-off (focus stays on the avatar until the host bumps
/// `focusEntryToken` on d-pad down, then lands on the first row).
struct TVProfileDropdown: View {
    let profileName: String
    let avatar: String?
    /// Display name of the active server, shown under the profile name in
    /// the §5.8 mono header style.
    let serverHost: String?
    let isAdmin: Bool
    /// Whether focus has entered the panel (host flips on d-pad down).
    let entersPanel: Bool
    /// Bumped by the host when focus should enter — lands on the first row.
    let focusEntryToken: Int
    /// Reports whether any row currently holds focus, so the host can drop
    /// the avatar's focus ring once focus descends (§5.8).
    let onPanelFocusChanged: (Bool) -> Void
    let onSwitchProfile: () -> Void
    let onWatchlist: () -> Void
    let onFavorites: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void
    let onAdminDashboard: () -> Void
    let onSwitchServer: () -> Void
    let onSignOut: () -> Void

    @FocusState private var focusedAction: TVProfileAction?
    @State private var lastAppliedEntryToken = 0

    var body: some View {
        panel
            // Inert until the host hands focus in on d-pad down (§5.8) — the
            // avatar keeps focus while the menu is merely open, and the down
            // press reaches the avatar's `onMoveCommand` instead of the
            // engine grabbing a row first.
            .disabled(!entersPanel)
            .onChange(of: focusEntryToken) { _, token in applyEntryToken(token) }
            .onChange(of: focusedAction) { _, newValue in
                onPanelFocusChanged(newValue != nil)
            }
            .onChange(of: entersPanel) { _, entered in
                if !entered { focusedAction = nil }
            }
            .onAppear {
                if entersPanel { applyEntryToken(focusEntryToken) }
            }
    }

    private func applyEntryToken(_ token: Int) {
        guard entersPanel, token > 0, token != lastAppliedEntryToken else { return }
        lastAppliedEntryToken = token
        focusedAction = .switchProfile
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
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile menu")
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
