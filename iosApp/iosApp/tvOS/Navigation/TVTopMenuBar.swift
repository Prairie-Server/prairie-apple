#if os(tvOS)
import SwiftUI

enum TVTopMenuLayout {
    /// Vertical clearance needed when a root tvOS page does not render a
    /// full-bleed hero behind the custom top menu.
    static let contentTopInset: CGFloat = 188
    static let primaryTopInset: CGFloat = 16
    static let primaryRowHeight: CGFloat = 54
    static let headerBandHeight: CGFloat = 92
    static let profileMenuTopInset: CGFloat = 92
    static let searchButtonWidth: CGFloat = 82
    static let homeButtonWidth: CGFloat = 136
    static let librariesButtonWidth: CGFloat = 196
    static let forYouButtonWidth: CGFloat = 164
    static let calendarButtonWidth: CGFloat = 186
    static let librarySwitcherWidth: CGFloat = 218
    static let librarySwitcherHeight: CGFloat = 46
    static let librarySwitcherFocusPadding: CGFloat = 14
    static let libraryModeWidth: CGFloat = 314
    static let libraryModeFocusPadding: CGFloat = 12
    static let libraryAccessoryHeight: CGFloat = 52
    static let rootTextSize: CGFloat = 24
    static let libraryMenuLeadingInset: CGFloat = 128
}

enum TVRootDestination: String, CaseIterable, Identifiable, Hashable {
    case home = "Home"
    case search = "Search"
    case libraries = "Libraries"
    case forYou = "For You"
    case calendar = "Calendar"

    var id: String { rawValue }
}

struct TVLibraryMenuOption: Identifiable, Equatable {
    let id: Int
    let name: String
    let typeLabel: String
    let iconName: String
}

struct TVLibraryHeaderContext: Equatable {
    let id: Int
    let name: String
    let typeLabel: String
    let iconName: String
    let canSwitchLibrary: Bool
    let options: [TVLibraryMenuOption]
}

struct TVTopMenuBar: View {
    let selectedRoot: TVRootDestination
    let currentProfile: UserProfile?
    let libraryHeaderContext: TVLibraryHeaderContext?
    let libraryMode: TVLibraryLandingMode
    @Binding var isMenuFocused: Bool
    let isFocusSuppressed: Bool
    let focusRequest: Int
    let onSelectRoot: (TVRootDestination) -> Void
    let onSelectLibraryMode: (TVLibraryLandingMode) -> Void
    let onSelectLibrary: (Int) -> Void
    let onSwitchProfile: () -> Void
    let onSwitchServer: () -> Void
    let onSettings: () -> Void
    let onSignOut: () -> Void
    var onExit: (() -> Void)? = nil

    @State private var showsProfileActions = false
    @State private var showsLibraryActions = false
    @FocusState private var focusedItem: TVTopMenuFocus?

    var body: some View {
        ZStack(alignment: .top) {
            topScrim

            HStack(spacing: 34) {
                iconButton(
                    systemImage: "magnifyingglass",
                    label: "Search",
                    isSelected: selectedRoot == .search,
                    isFocused: focusedItem == .search,
                    action: { selectRootFromMenu(.search) }
                )

                rootButton(.home)

                rootButton(.libraries)

                rootButton(.forYou)

                rootButton(.calendar)
            }
            .frame(height: TVTopMenuLayout.primaryRowHeight, alignment: .top)
            .padding(.top, TVTopMenuLayout.primaryTopInset)
            .frame(maxWidth: .infinity, alignment: .top)
            .zIndex(1)

            HStack(spacing: 16) {
                profileButton

                librarySwitcherAccessory

                Spacer(minLength: 0)
            }
            .frame(height: TVTopMenuLayout.primaryRowHeight, alignment: .top)
            .padding(.leading, 44)
            .padding(.top, TVTopMenuLayout.primaryTopInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .zIndex(1)

            libraryModeAccessory
                .frame(height: TVTopMenuLayout.primaryRowHeight, alignment: .top)
                .padding(.trailing, 86)
                .padding(.top, TVTopMenuLayout.primaryTopInset)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(minHeight: TVTopMenuLayout.headerBandHeight, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .focusSection()
        .animation(ContinuumTheme.springAnimation, value: showsProfileActions)
        .animation(ContinuumTheme.springAnimation, value: showsLibraryActions)
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
        .fullScreenCover(isPresented: $showsLibraryActions) {
            libraryMenuPresentation
                .presentationBackground(.clear)
        }
    }

    private var topScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.84), location: 0.0),
                .init(color: Color.black.opacity(0.72), location: 0.58),
                .init(color: Color.black.opacity(0.36), location: 0.88),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: TVTopMenuLayout.headerBandHeight)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var profileButton: some View {
        Button {
            showsLibraryActions = false
            showsProfileActions = true
        } label: {
            HStack(spacing: 14) {
                ProfileAvatarView(
                    avatar: currentProfile?.avatarEmoji,
                    name: currentProfile?.name ?? "",
                    size: 44,
                    backgroundColor: Color.white.opacity(0.18),
                    textColor: .white
                )

                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(profileForegroundColor)
            }
            .frame(height: TVTopMenuLayout.primaryRowHeight)
            .padding(.horizontal, 8)
            .modifier(
                TVTopMenuButtonChrome(
                    isSelected: false,
                    isFocused: focusedItem == .profile
                )
            )
            .animation(ContinuumTheme.springAnimation, value: focusedItem)
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedItem, equals: .profile)
        .accessibilityLabel("Profile")
    }

    private var profileMenuPresentation: some View {
        TVProfileActionsModal(
            profileName: currentProfile?.name ?? "Profile",
            avatar: currentProfile?.avatarEmoji,
            onSwitchProfile: { dismissProfileMenu(then: onSwitchProfile) },
            onSwitchServer: { dismissProfileMenu(then: onSwitchServer) },
            onSettings: { dismissProfileMenu(then: onSettings) },
            onSignOut: { dismissProfileMenu(then: onSignOut) },
            onDismiss: { showsProfileActions = false }
        )
    }

    @ViewBuilder
    private var libraryMenuPresentation: some View {
        if let libraryHeaderContext {
            TVLibraryActionsModal(
                context: libraryHeaderContext,
                onSelect: { libraryID in
                    showsLibraryActions = false
                    onSelectLibrary(libraryID)
                },
                onDismiss: { showsLibraryActions = false }
            )
        } else {
            Color.clear
                .ignoresSafeArea()
                .onAppear {
                    showsLibraryActions = false
                }
        }
    }

    private var profileForegroundColor: Color {
        focusedItem == .profile ? .white : .white.opacity(0.78)
    }

    private func dismissProfileMenu(then action: @escaping () -> Void) {
        showsProfileActions = false
        DispatchQueue.main.async {
            action()
        }
    }

    private func rootButton(_ root: TVRootDestination) -> some View {
        let isFocused = focusedItem == .root(root)
        let isSelected = selectedRoot == root

        return Button {
            selectRootFromMenu(root)
        } label: {
            Text(root.rawValue)
                .font(.system(size: TVTopMenuLayout.rootTextSize, weight: isSelected || isFocused ? .semibold : .regular))
                .foregroundStyle(isSelected || isFocused ? .white : .white.opacity(0.70))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: rootButtonWidth(for: root), height: TVTopMenuLayout.primaryRowHeight)
                .modifier(
                    TVTopMenuButtonChrome(
                        isSelected: isSelected,
                        isFocused: isFocused
                    )
                )
                .animation(ContinuumTheme.springAnimation, value: isFocused)
                .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedItem, equals: .root(root))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectRootFromMenu(_ root: TVRootDestination) {
        onSelectRoot(root)
        DispatchQueue.main.async {
            focusedItem = nil
        }
    }

    private func menuFocusTarget(for root: TVRootDestination) -> TVTopMenuFocus {
        root == .search ? .search : .root(root)
    }

    private func requestMenuFocus() {
        let target = menuFocusTarget(for: selectedRoot)
        DispatchQueue.main.async {
            guard !isFocusSuppressed else { return }
            focusedItem = target
        }
    }

    private func rootButtonWidth(for root: TVRootDestination) -> CGFloat {
        switch root {
        case .home:
            return TVTopMenuLayout.homeButtonWidth
        case .search:
            return TVTopMenuLayout.searchButtonWidth
        case .libraries:
            return TVTopMenuLayout.librariesButtonWidth
        case .forYou:
            return TVTopMenuLayout.forYouButtonWidth
        case .calendar:
            return TVTopMenuLayout.calendarButtonWidth
        }
    }

    private func iconButton(
        systemImage: String,
        label: String,
        isSelected: Bool,
        isFocused: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(iconForegroundColor(isSelected: isSelected, isFocused: isFocused))
                .frame(width: TVTopMenuLayout.searchButtonWidth, height: TVTopMenuLayout.primaryRowHeight)
                .modifier(
                    TVTopMenuButtonChrome(
                        isSelected: isSelected,
                        isFocused: isFocused
                    )
                )
                .animation(ContinuumTheme.springAnimation, value: isFocused)
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedItem, equals: .search)
        .accessibilityLabel(label)
    }

    private func iconForegroundColor(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused || isSelected {
            return .white
        }
        return .white.opacity(0.72)
    }

    @ViewBuilder
    private var librarySwitcherAccessory: some View {
        if selectedRoot == .libraries {
            if let libraryHeaderContext {
                Button {
                    showsProfileActions = false
                    showsLibraryActions = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: libraryHeaderContext.iconName)
                            .font(.system(size: 16, weight: .semibold))

                        VStack(alignment: .leading, spacing: 0) {
                            Text(libraryHeaderContext.typeLabel.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.2)
                                .opacity(0.58)

                            Text(libraryHeaderContext.name)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                        }

                        if libraryHeaderContext.canSwitchLibrary {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(0.70)
                        }
                    }
                    .foregroundStyle(libraryAccessoryForeground(isSelected: false, isFocused: focusedItem == .librarySwitcher))
                    .padding(.horizontal, 12)
                    .frame(width: TVTopMenuLayout.librarySwitcherWidth, height: TVTopMenuLayout.librarySwitcherHeight, alignment: .leading)
                    .modifier(
                        TVTopMenuButtonChrome(
                            isSelected: false,
                            isFocused: focusedItem == .librarySwitcher
                        )
                    )
                }
                .buttonStyle(.continuumFlat)
                .disabled(!libraryHeaderContext.canSwitchLibrary)
                .focused($focusedItem, equals: .librarySwitcher)
                .accessibilityLabel("Switch Library")
                .padding(.horizontal, TVTopMenuLayout.librarySwitcherFocusPadding)
                .padding(.vertical, 4)
            } else {
                Color.clear
                    .frame(
                        width: TVTopMenuLayout.librarySwitcherWidth + (TVTopMenuLayout.librarySwitcherFocusPadding * 2),
                        height: TVTopMenuLayout.primaryRowHeight
                    )
            }
        }
    }

    @ViewBuilder
    private var libraryModeAccessory: some View {
        if selectedRoot == .libraries {
            if libraryHeaderContext != nil {
                TVLibraryModeSlider(
                    selectedMode: libraryMode,
                    focusedItem: $focusedItem,
                    onSelectMode: onSelectLibraryMode
                )
                .focusSection()
                .padding(.horizontal, TVTopMenuLayout.libraryModeFocusPadding)
                .accessibilityLabel("Library view")
                .accessibilityValue(libraryMode.title)
            } else {
                Color.clear
                    .frame(
                        width: TVTopMenuLayout.libraryModeWidth + (TVTopMenuLayout.libraryModeFocusPadding * 2),
                        height: TVTopMenuLayout.libraryAccessoryHeight
                    )
            }
        }
    }

    private func libraryAccessoryForeground(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused || isSelected { return .white }
        return Color.continuumOnSurface.opacity(0.76)
    }

}

private enum TVTopMenuFocus: Hashable {
    case profile
    case search
    case root(TVRootDestination)
    case librarySwitcher
    case libraryMode(TVLibraryLandingMode)
}

private enum TVProfileAction: Hashable {
    case switchProfile
    case switchServer
    case settings
    case signOut
    case cancel
}

private struct TVLibraryModeSlider: View {
    let selectedMode: TVLibraryLandingMode
    @FocusState.Binding var focusedItem: TVTopMenuFocus?
    let onSelectMode: (TVLibraryLandingMode) -> Void

    private let segmentWidth: CGFloat = 152
    private let segmentHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 0) {
            segmentButton(.recommended)
            segmentButton(.collections)
        }
        .padding(5)
        .background(
            Capsule()
                .fill(Color.black.opacity(isControlFocused ? 0.46 : 0.28))
        )
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(isControlFocused ? 0.56 : 0.14), lineWidth: isControlFocused ? 1.5 : 1)
        }
        .scaleEffect(isControlFocused ? 1.025 : 1.0)
        .animation(ContinuumTheme.springAnimation, value: selectedMode)
        .animation(ContinuumTheme.springAnimation, value: focusedItem)
    }

    private func segmentButton(_ mode: TVLibraryLandingMode) -> some View {
        let isSelected = selectedMode == mode
        let isFocused = focusedItem == .libraryMode(mode)

        return Button {
            onSelectMode(mode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 13, weight: .bold))

                Text(mode.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(segmentForeground(isSelected: isSelected, isFocused: isFocused))
            .frame(width: segmentWidth, height: segmentHeight)
            .background(
                Capsule()
                    .fill(segmentFill(isSelected: isSelected, isFocused: isFocused))
            )
            .shadow(color: .black.opacity(isFocused ? 0.32 : 0), radius: isFocused ? 10 : 0, y: 4)
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedItem, equals: .libraryMode(mode))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onChange(of: isFocused) { _, newValue in
            if newValue, selectedMode != mode {
                onSelectMode(mode)
            }
        }
    }

    private var isControlFocused: Bool {
        focusedItem == .libraryMode(.recommended) || focusedItem == .libraryMode(.collections)
    }

    private func segmentFill(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused { return Color.white.opacity(0.94) }
        if isSelected { return Color.white.opacity(0.18) }
        return .clear
    }

    private func segmentForeground(isSelected: Bool, isFocused: Bool) -> Color {
        if isFocused { return .continuumBackground }
        if isSelected { return .white }
        return .white.opacity(isControlFocused ? 0.70 : 0.54)
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

private struct TVProfileActionsPanel: View {
    let profileName: String
    let avatar: String?
    let onSwitchProfile: () -> Void
    let onSwitchServer: () -> Void
    let onSettings: () -> Void
    let onSignOut: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedAction: TVProfileAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ProfileAvatarView(
                    avatar: avatar,
                    name: profileName,
                    size: 50,
                    backgroundColor: Color.white.opacity(0.16),
                    textColor: .white
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.52))

                    Text(profileName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            VStack(spacing: 8) {
                actionButton(
                    title: "Switch Profile",
                    systemImage: "person.2.fill",
                    actionID: .switchProfile,
                    action: onSwitchProfile
                )
                actionButton(
                    title: "Switch Server",
                    systemImage: "server.rack",
                    actionID: .switchServer,
                    action: onSwitchServer
                )
                actionButton(
                    title: "Settings",
                    systemImage: "gearshape.fill",
                    actionID: .settings,
                    action: onSettings
                )
                actionButton(
                    title: "Sign Out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    actionID: .signOut,
                    isDestructive: true,
                    action: onSignOut
                )
                actionButton(
                    title: "Cancel",
                    systemImage: "xmark",
                    actionID: .cancel,
                    action: onDismiss
                )
            }
        }
        .padding(22)
        .frame(width: 390, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 34, y: 18)
        .focusSection()
        .onAppear {
            focusedAction = .switchProfile
        }
        .onExitCommand(perform: onDismiss)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        actionID: TVProfileAction,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 28)

                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(TVProfileMenuButtonStyle(isDestructive: isDestructive))
        .focused($focusedAction, equals: actionID)
    }
}

private struct TVProfileActionsModal: View {
    let profileName: String
    let avatar: String?
    let onSwitchProfile: () -> Void
    let onSwitchServer: () -> Void
    let onSettings: () -> Void
    let onSignOut: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()

            TVProfileActionsPanel(
                profileName: profileName,
                avatar: avatar,
                onSwitchProfile: onSwitchProfile,
                onSwitchServer: onSwitchServer,
                onSettings: onSettings,
                onSignOut: onSignOut,
                onDismiss: onDismiss
            )
            .padding(.leading, 44)
            .padding(.top, TVTopMenuLayout.profileMenuTopInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

private struct TVLibraryActionsPanel: View {
    let title: String
    let options: [TVLibraryMenuOption]
    let selectedLibraryID: Int
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedLibraryID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))

                Text(selectedLibraryName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(options) { option in
                            libraryButton(option)
                                .id(option.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 430)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: focusedLibraryID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(ContinuumTheme.springAnimation) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 430, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 34, y: 18)
        .focusSection()
        .onAppear {
            focusedLibraryID = initialFocusedLibraryID
        }
        .onExitCommand(perform: onDismiss)
    }

    private var selectedLibraryName: String {
        options.first(where: { $0.id == selectedLibraryID })?.name ?? "Choose Library"
    }

    private func libraryButton(_ option: TVLibraryMenuOption) -> some View {
        Button {
            onSelect(option.id)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.iconName)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.name)
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)

                    Text(option.typeLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .opacity(0.64)
                }

                Spacer(minLength: 0)

                if option.id == selectedLibraryID {
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .bold))
                }
            }
        }
        .buttonStyle(
            TVProfileMenuButtonStyle(
                isDestructive: false,
                horizontalPadding: 14,
                verticalPadding: 11,
                focusedScale: 1.0
            )
        )
        .focused($focusedLibraryID, equals: option.id)
        .accessibilityAddTraits(option.id == selectedLibraryID ? .isSelected : [])
    }

    private var initialFocusedLibraryID: Int? {
        if options.contains(where: { $0.id == selectedLibraryID }) {
            return selectedLibraryID
        }
        return options.first?.id
    }

}

private struct TVLibraryActionsModal: View {
    let context: TVLibraryHeaderContext
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()

            TVLibraryActionsPanel(
                title: "Library",
                options: context.options,
                selectedLibraryID: context.id,
                onSelect: onSelect,
                onDismiss: onDismiss
            )
            .padding(.leading, TVTopMenuLayout.libraryMenuLeadingInset)
            .padding(.top, TVTopMenuLayout.profileMenuTopInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

private struct TVProfileMenuButtonStyle: ButtonStyle {
    let isDestructive: Bool
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 14
    var focusedScale: CGFloat = 1.02

    func makeBody(configuration: Configuration) -> some View {
        TVProfileMenuButtonBody(
            configuration: configuration,
            isDestructive: isDestructive,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            focusedScale: focusedScale
        )
    }
}

private struct TVProfileMenuButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isDestructive: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let focusedScale: CGFloat

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            }
            .scaleEffect(isFocused ? focusedScale : 1.0)
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

    private var backgroundColor: Color {
        isFocused ? Color.white.opacity(0.94) : Color.white.opacity(0.06)
    }

    private var borderColor: Color {
        isFocused ? Color.white : Color.white.opacity(0.08)
    }
}

private struct TVTopMenuTextButton: View {
    let title: String
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: TVTopMenuLayout.rootTextSize, weight: fontWeight))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(height: TVTopMenuLayout.primaryRowHeight)
                .padding(.horizontal, 22)
                .modifier(
                    TVTopMenuButtonChrome(
                        isSelected: isSelected,
                        isFocused: isFocused
                    )
                )
                .animation(ContinuumTheme.springAnimation, value: isFocused)
                .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.continuumFlat)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fontWeight: Font.Weight {
        isSelected || isFocused ? .semibold : .regular
    }

    private var foregroundColor: Color {
        if isFocused || isSelected {
            return .white
        }
        return .white.opacity(0.70)
    }
}

private struct TVTopMenuButtonChrome: ViewModifier {
    let isSelected: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            }
            .shadow(color: isFocused ? .white.opacity(0.08) : .clear, radius: 10)
            .scaleEffect(isFocused ? 1.025 : 1.0)
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    private var backgroundColor: Color {
        if isFocused { return Color.white.opacity(0.12) }
        if isSelected { return Color.white.opacity(0.08) }
        return .clear
    }

    private var borderColor: Color {
        if isFocused { return Color.white.opacity(0.28) }
        if isSelected { return Color.white.opacity(0.14) }
        return .clear
    }
}
#endif
