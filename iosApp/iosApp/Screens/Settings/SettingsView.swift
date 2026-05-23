import SwiftUI

/// App settings screen.
///
/// Modeled after native iOS Settings + media-app peers (VidHub, Infuse):
/// account header card up top, grouped sections with icon-in-rounded-square
/// row labels, and drilldowns to dedicated sub-screens for compound
/// preferences like Playback and Subtitles.
///
/// On tvOS this view delegates to ``TVSettingsView``, which is a two-pane
/// master/detail layout tuned for the 10-foot experience.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(AppRouter.self) private var router
    @State private var showSignOutConfirm = false

    var body: some View {
        #if os(tvOS)
        TVSettingsView()
        #else
        iosBody
        #endif
    }

    #if !os(tvOS)
    private var iosBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            settingsStack
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 36)
        }
        .background {
            SettingsBackdrop()
        }
        .navigationTitle("Settings")
        .continuumNavigationTitleDisplayMode(.large)
        .continuumToolbarColorSchemeDark()
        .continuumNavigationBarBackgroundHidden()
        .task {
            await viewModel.loadSettings()
        }
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                router.signOutAndReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    @ViewBuilder
    private var settingsStack: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: 18) {
                settingsSections
            }
        } else {
            settingsSections
        }
    }

    private var settingsSections: some View {
        VStack(spacing: 18) {
            accountHeader
            preferencesSection
            librarySection
            serverSection
            aboutSection
            signOutSection
        }
    }

    // MARK: - Account header

    private var accountHeader: some View {
        SettingsCardSurface(tint: Color.white.opacity(0.09), isInteractive: true) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    AuthService.shared.profileId = nil
                    router.showProfileSelection()
                } label: {
                    HStack(spacing: 16) {
                        ProfileAvatarView(
                            avatar: viewModel.activeProfile?.avatarEmoji,
                            name: viewModel.activeProfile?.name
                                ?? viewModel.userInfo?.username
                                ?? "",
                            size: 60
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.continuumOnSurface)

                            Text(subtitleLine)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.continuumSecondaryText)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.continuumSecondaryText.opacity(0.85))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if viewModel.userInfo?.isAdmin == true {
                    SettingsStatusChip(
                        title: "Administrator",
                        systemImage: "checkmark.shield.fill",
                        tint: .indigo.opacity(0.18)
                    )
                }

                if viewModel.userInfo?.isAdmin == true {
                    SettingsCardDivider()

                    NavigationLink {
                        AdminDashboardView()
                    } label: {
                        SettingsCardRowContent(
                            title: "Admin Dashboard",
                            subtitle: "Users, activity, and server tools",
                            detail: nil,
                            systemImage: "wrench.and.screwdriver.fill",
                            iconColor: .indigo,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var displayName: String {
        if let name = viewModel.activeProfile?.name, !name.isEmpty {
            return name
        }
        if let username = viewModel.userInfo?.username, !username.isEmpty {
            return username
        }
        return "Switch Profile"
    }

    private var subtitleLine: String {
        let host = serverHost
        let username = viewModel.userInfo?.username
        switch (username, host) {
        case let (user?, host?) where !user.isEmpty && user != displayName:
            return "\(user) · \(host)"
        case let (_, host?):
            return host
        case let (user?, _) where !user.isEmpty && user != displayName:
            return user
        default:
            return "Tap to switch profile"
        }
    }

    private var serverHost: String? {
        guard let url = URL(string: viewModel.serverUrl), let host = url.host else {
            return viewModel.serverUrl.isEmpty ? nil : viewModel.serverUrl
        }
        return host
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        SettingsSectionCard(
            title: "Preferences",
            subtitle: "Playback, subtitles, and language defaults",
            tint: .blue.opacity(0.16)
        ) {
            VStack(spacing: 0) {
                NavigationLink {
                    PlaybackSettingsView(viewModel: viewModel)
                } label: {
                    SettingsCardRowContent(
                        title: "Playback",
                        subtitle: "Quality, autoplay, and intro behavior",
                        detail: qualityDisplayName(viewModel.preferredQuality),
                        systemImage: "play.fill",
                        iconColor: .blue,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                SettingsCardDivider()

                NavigationLink {
                    SubtitleSettingsView(viewModel: viewModel)
                } label: {
                    SettingsCardRowContent(
                        title: "Subtitles",
                        subtitle: "Language, behavior, and appearance",
                        detail: subtitleLanguageName(viewModel.editorSubtitleLanguage),
                        systemImage: "captions.bubble.fill",
                        iconColor: .pink,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                SettingsCardDivider()

                NavigationLink {
                    CardOverlaySettingsView()
                } label: {
                    SettingsCardRowContent(
                        title: "Card Overlays",
                        subtitle: "Badges shown on poster cards (resolution, ratings, etc.)",
                        detail: nil,
                        systemImage: "rectangle.stack.badge.plus",
                        iconColor: .indigo,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Library shortcuts

    private var librarySection: some View {
        SettingsSectionCard(
            title: "Library",
            subtitle: "Shortcuts to your shelves and history",
            tint: .orange.opacity(0.16)
        ) {
            VStack(spacing: 0) {
                NavigationLink {
                    WatchlistView()
                } label: {
                    SettingsCardRowContent(
                        title: "Watchlist",
                        subtitle: "Items you saved for later",
                        detail: nil,
                        systemImage: "bookmark.fill",
                        iconColor: .orange,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                SettingsCardDivider()

                NavigationLink {
                    FavoritesView()
                } label: {
                    SettingsCardRowContent(
                        title: "Favorites",
                        subtitle: "Items you marked as favorites",
                        detail: nil,
                        systemImage: "heart.fill",
                        iconColor: .red,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                SettingsCardDivider()

                NavigationLink {
                    HistoryView()
                } label: {
                    SettingsCardRowContent(
                        title: "Watch History",
                        subtitle: "Finished and partially watched items",
                        detail: nil,
                        systemImage: "clock.fill",
                        iconColor: .gray,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                SettingsCardDivider()

                NavigationLink {
                    CollectionsView()
                } label: {
                    SettingsCardRowContent(
                        title: "Collections",
                        subtitle: "Grouped picks and custom sets",
                        detail: nil,
                        systemImage: "square.stack.fill",
                        iconColor: .purple,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Server

    private var serverSection: some View {
        SettingsSectionCard(
            title: "Connection",
            subtitle: "Server connection and switching",
            tint: .teal.opacity(0.16)
        ) {
            Button {
                router.navigate(to: .serverList)
            } label: {
                SettingsCardRowContent(
                    title: "Server",
                    subtitle: "Current server",
                    detail: viewModel.serverDisplayName,
                    systemImage: "server.rack",
                    iconColor: .teal,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSectionCard(
            title: "About",
            subtitle: "Build information",
            tint: .gray.opacity(0.16)
        ) {
            SettingsCardRowContent(
                title: "Version",
                subtitle: "Installed app build",
                detail: versionString,
                systemImage: "info.circle.fill",
                iconColor: .gray,
                showsChevron: false
            )
        }
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            SettingsCardSurface(tint: .red.opacity(0.18), isInteractive: true) {
                HStack {
                    Spacer()
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.red.opacity(0.95))
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }
    #endif
}

#if !os(tvOS)

// MARK: - Reusable row primitives

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let tint: Color
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        SettingsCardSurface(tint: tint) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.continuumOnSurface)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.continuumSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
            }
        }
    }
}

private struct SettingsCardSurface<Content: View>: View {
    let tint: Color
    let isInteractive: Bool
    let content: Content

    init(
        tint: Color,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .modifier(SettingsCardChrome(tint: tint, isInteractive: isInteractive))
    }
}

private struct SettingsCardChrome: ViewModifier {
    let tint: Color
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        if #available(iOS 26, macOS 26, *) {
            let glass = isInteractive
                ? Glass.regular.tint(tint).interactive()
                : Glass.regular.tint(tint)

            content
                .glassEffect(glass, in: .rect(cornerRadius: 30))
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                }
        } else {
            content
                .background(shape.fill(Color.continuumSurfaceElevated.opacity(0.86)))
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct SettingsCardRowContent: View {
    let title: String
    let subtitle: String?
    let detail: String?
    let systemImage: String
    let iconColor: Color
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIconBadge(systemImage: systemImage, color: iconColor)

            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    titleLine
                    compactTitleLine
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.continuumSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.continuumSecondaryText.opacity(0.8))
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.continuumOnSurface)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let detail {
                detailText(detail)
            }
        }
    }

    private var compactTitleLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.continuumOnSurface)
                .lineLimit(1)

            if let detail {
                detailText(detail)
            }
        }
    }

    private func detailText(_ detail: String) -> some View {
        Text(detail)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.continuumOnSurface.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

private struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 52)
    }
}

private struct SettingsStatusChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.continuumOnSurface)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.continuumOnSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(SettingsChipChrome(tint: tint))
    }
}

private struct SettingsChipChrome: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(.regular.tint(tint), in: .capsule)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                }
        } else {
            content
                .background(Capsule().fill(Color.continuumSurface.opacity(0.82)))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct SettingsIconBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color.gradient)
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
    }
}

private struct SettingsSubpageHero: View {
    let title: String
    let summary: String
    let systemImage: String
    let tint: Color

    var body: some View {
        SettingsCardSurface(tint: tint.opacity(0.18)) {
            HStack(alignment: .top, spacing: 16) {
                SettingsIconBadge(systemImage: systemImage, color: tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.continuumOnSurface)

                    Text(summary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.continuumSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SettingsBackdrop: View {
    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 120)
                .offset(x: 150, y: -240)

            Circle()
                .fill(Color.teal.opacity(0.14))
                .frame(width: 340, height: 340)
                .blur(radius: 170)
                .offset(x: -140, y: 80)

            Circle()
                .fill(Color.orange.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 140)
                .offset(x: 120, y: 420)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear,
                    Color.continuumBackground.opacity(0.92),
                    Color.continuumBackground,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Playback sub-screen

struct PlaybackSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section {
                SettingsSubpageHero(
                    title: "Playback",
                    summary: "Tune streaming quality and automatic episode behavior for this device.",
                    systemImage: "play.rectangle.on.rectangle.fill",
                    tint: .blue
                )
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Picker("Quality", selection: Binding(
                    get: { viewModel.preferredQuality },
                    set: { newValue in
                        viewModel.preferredQuality = newValue
                        Task { await viewModel.setPreferredQuality(newValue) }
                    }
                )) {
                    ForEach(qualityOptions, id: \.0) { tag, label in
                        Text(label).tag(tag)
                    }
                }
                .foregroundColor(.continuumOnSurface)
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif

                Toggle("Profile 7 HDR10 Fallback", isOn: Binding(
                    get: { viewModel.preferProfile7HDR10Fallback },
                    set: { enabled in
                        viewModel.preferProfile7HDR10Fallback = enabled
                        Task { await viewModel.setPreferProfile7HDR10Fallback(enabled) }
                    }
                ))
                    .foregroundColor(.continuumOnSurface)
                    .tint(.continuumOnSurface)

                Picker("Audio Language", selection: Binding(
                    get: { viewModel.preferredAudioLanguage },
                    set: { newValue in
                        viewModel.preferredAudioLanguage = newValue
                        Task { await viewModel.setPreferredAudioLanguage(newValue) }
                    }
                )) {
                    ForEach(audioLanguageOptions, id: \.0) { tag, label in
                        Text(label).tag(tag)
                    }
                }
                .foregroundColor(.continuumOnSurface)
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } header: {
                Text("Streaming")
                    .foregroundColor(.continuumSecondaryText)
            } footer: {
                Text("The fallback plays Dolby Vision Profile 7 as HDR10 on this device.")
                    .foregroundColor(.continuumSecondaryText)
            }
            .listRowBackground(Color.continuumSurfaceElevated)

            Section {
                Toggle("Auto-play next episode", isOn: Binding(
                    get: { viewModel.autoPlayNext },
                    set: { enabled in
                        viewModel.autoPlayNext = enabled
                        Task { await viewModel.setAutoPlayNext(enabled) }
                    }
                ))
                    .foregroundColor(.continuumOnSurface)
                    .tint(.continuumOnSurface)

                Picker("Show Next Up", selection: Binding(
                    get: { viewModel.nextUpPromptSeconds },
                    set: { newValue in
                        viewModel.nextUpPromptSeconds = newValue
                        Task { await viewModel.setNextUpPromptSeconds(newValue) }
                    }
                )) {
                    ForEach(nextUpPromptOptions, id: \.0) { seconds, label in
                        Text(label).tag(seconds)
                    }
                }
                .foregroundColor(.continuumOnSurface)
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif

                Toggle("Skip intros", isOn: Binding(
                    get: { viewModel.skipIntros },
                    set: { enabled in
                        viewModel.skipIntros = enabled
                        Task { await viewModel.setSkipIntros(enabled) }
                    }
                ))
                    .foregroundColor(.continuumOnSurface)
                    .tint(.continuumOnSurface)

                Toggle("Skip credits", isOn: Binding(
                    get: { viewModel.skipCredits },
                    set: { enabled in
                        viewModel.skipCredits = enabled
                        Task { await viewModel.setSkipCredits(enabled) }
                    }
                ))
                    .foregroundColor(.continuumOnSurface)
                    .tint(.continuumOnSurface)
            } header: {
                Text("Playback Behavior")
                    .foregroundColor(.continuumSecondaryText)
            }
            .listRowBackground(Color.continuumSurfaceElevated)

            Section {
                Button(role: .destructive) {
                    Task { await viewModel.resetPlaybackDeviceSettings() }
                } label: {
                    Text("Reset Playback Overrides")
                }
            } footer: {
                Text("Resets playback choices for this device and profile back to the server fallback.")
                    .foregroundColor(.continuumSecondaryText)
            }
            .listRowBackground(Color.continuumSurfaceElevated)
        }
        #if !os(macOS)
        .listSectionSpacing(18)
        #endif
        .continuumGroupedListStyle()
        .continuumScrollContentBackgroundHidden()
        .background {
            SettingsBackdrop()
        }
        .navigationTitle("Playback")
        .continuumNavigationTitleDisplayMode(.inline)
        .continuumToolbarColorSchemeDark()
        .continuumNavigationBarBackgroundHidden()
    }

    private var qualityOptions: [(String, String)] {
        ApplePlaybackQuality.settingsOptions.map { ($0.id, $0.labelWithBitrate) }
    }

    private var audioLanguageOptions: [(String, String)] {
        [
            ("", "Default"),
            ("en", "English"),
            ("es", "Spanish"),
            ("fr", "French"),
            ("de", "German"),
            ("it", "Italian"),
            ("pt", "Portuguese"),
            ("ja", "Japanese"),
            ("ko", "Korean"),
        ]
    }

    private var nextUpPromptOptions: [(Int, String)] {
        [
            (0, "At end"),
            (10, "10 seconds before end"),
            (30, "30 seconds before end"),
            (60, "1 minute before end"),
            (120, "2 minutes before end"),
        ]
    }
}

// MARK: - Subtitles sub-screen

struct SubtitleSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section {
                SettingsSubpageHero(
                    title: "Subtitles",
                    summary: "Choose your preferred subtitle language, behavior, and appearance.",
                    systemImage: "captions.bubble.fill",
                    tint: .pink
                )
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            profileBackedSection
            appearanceSection
        }
        #if !os(macOS)
        .listSectionSpacing(18)
        #endif
        .continuumGroupedListStyle()
        .continuumScrollContentBackgroundHidden()
        .background {
            SettingsBackdrop()
        }
        .navigationTitle("Subtitles")
        .continuumNavigationTitleDisplayMode(.inline)
        .continuumToolbarColorSchemeDark()
        .continuumNavigationBarBackgroundHidden()
        .onChange(of: viewModel.editorSubtitleLanguage) { _, _ in
            Task { await viewModel.saveProfilePrefs() }
        }
        .onChange(of: viewModel.editorSubtitleMode) { _, _ in
            Task { await viewModel.saveProfilePrefs() }
        }
        .onChange(of: viewModel.editorShowForcedSubtitles) { _, _ in
            Task { await viewModel.saveProfilePrefs() }
        }
    }

    @ViewBuilder
    private var profileBackedSection: some View {
        Section {
            Picker("Language", selection: $viewModel.editorSubtitleLanguage) {
                Text("None").tag(PlaybackPrefSentinel.none)
                ForEach(PlaybackLanguageOption.all) { option in
                    Text(option.label).tag(option.code)
                }
            }
            .foregroundColor(.continuumOnSurface)
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.navigationLink)
            #endif

            Picker("Behavior", selection: $viewModel.editorSubtitleMode) {
                ForEach(SubtitleMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayLabel).tag(mode.rawValue)
                }
            }
            .foregroundColor(.continuumOnSurface)
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.navigationLink)
            #endif

            Toggle(
                "Show Forced Subtitles",
                isOn: Binding(
                    get: { viewModel.editorShowForcedSubtitles == "on" },
                    set: { viewModel.editorShowForcedSubtitles = $0 ? "on" : "off" }
                )
            )
            .foregroundColor(.continuumOnSurface)
            .tint(.continuumOnSurface)
        } header: {
            Text("Profile")
                .foregroundColor(.continuumSecondaryText)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Used to pick a matching track when one is available. Forced subtitles cover foreign-language dialogue even when subtitles are off or set to auto.")
                if let state = viewModel.prefSaveState {
                    saveStateView(state)
                }
            }
            .foregroundColor(.continuumSecondaryText)
        }
        .listRowBackground(Color.continuumSurfaceElevated)
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Toggle(
                "Use custom appearance on this device",
                isOn: Binding(
                    get: { viewModel.subtitleUsesDeviceAppearanceOverride },
                    set: { enabled in
                        Task { await viewModel.setSubtitleDeviceOverrideEnabled(enabled) }
                    }
                )
            )
            .foregroundColor(.continuumOnSurface)
            .tint(.continuumOnSurface)

            Picker("Font Size", selection: appearanceBinding(\.fontSize)) {
                ForEach(SubtitleFontSizePreset.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .foregroundColor(.continuumOnSurface)
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.navigationLink)
            #endif

            Picker("Font Family", selection: appearanceBinding(\.fontFamily)) {
                ForEach(SubtitleFontFamilyPreset.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .foregroundColor(.continuumOnSurface)
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.navigationLink)
            #endif

            ColorSwatchPicker(
                title: "Font Color",
                colors: SubtitleAppearance.fontColors,
                selection: appearanceBinding(\.fontColor)
            )

            Toggle("Text Outline", isOn: appearanceBinding(\.textOutline))
                .foregroundColor(.continuumOnSurface)
                .tint(.continuumOnSurface)

            ColorSwatchPicker(
                title: "Outline Color",
                colors: SubtitleAppearance.outlineColors,
                selection: appearanceBinding(\.textOutlineColor)
            )
            .disabled(!viewModel.subtitleAppearance.textOutline && viewModel.subtitleAppearance.backgroundStyle != .outline)
            .opacity(viewModel.subtitleAppearance.textOutline || viewModel.subtitleAppearance.backgroundStyle == .outline ? 1 : 0.45)

            Picker("Background Style", selection: appearanceBinding(\.backgroundStyle)) {
                ForEach(SubtitleBackgroundStylePreset.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .foregroundColor(.continuumOnSurface)
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.navigationLink)
            #endif

            Picker("Background Opacity", selection: appearanceBinding(\.backgroundOpacity)) {
                ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { value in
                    Text("\(value)%").tag(value)
                }
            }
            .disabled(viewModel.subtitleAppearance.backgroundStyle != .box)
            .foregroundColor(.continuumOnSurface)
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.navigationLink)
            #endif

            ColorSwatchPicker(
                title: "Background Color",
                colors: SubtitleAppearance.backgroundColors,
                selection: appearanceBinding(\.backgroundColor)
            )
            .disabled(viewModel.subtitleAppearance.backgroundStyle != .box)
            .opacity(viewModel.subtitleAppearance.backgroundStyle == .box ? 1 : 0.45)

            Picker("Position", selection: appearanceBinding(\.position)) {
                ForEach(SubtitlePositionPreset.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .foregroundColor(.continuumOnSurface)
            #if os(macOS)
            .pickerStyle(.menu)
            #else
            .pickerStyle(.navigationLink)
            #endif
        } header: {
            Text(viewModel.subtitleUsesDeviceAppearanceOverride ? "This Device for This Profile" : "Server Fallback")
                .foregroundColor(.continuumSecondaryText)
        } footer: {
            Text(viewModel.subtitleUsesDeviceAppearanceOverride
                 ? "Saved on the server for this profile on this device. An admin can reset it."
                 : "Using the server fallback for this profile on this device. Turn the override on to save a custom appearance here.")
                .foregroundColor(.continuumSecondaryText)
        }
        .listRowBackground(Color.continuumSurfaceElevated)
    }

    private func appearanceBinding<Value: Equatable>(
        _ keyPath: WritableKeyPath<SubtitleAppearance, Value>
    ) -> Binding<Value> {
        Binding(
            get: { viewModel.subtitleAppearance[keyPath: keyPath] },
            set: { newValue in
                var next = viewModel.subtitleAppearance
                if next[keyPath: keyPath] == newValue { return }
                next[keyPath: keyPath] = newValue
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    @ViewBuilder
    private func saveStateView(_ state: SettingsViewModel.PrefSaveState) -> some View {
        switch state {
        case .saving:
            Text("Saving…")
        case .saved:
            Text("Saved")
        case .failed(let message):
            Text("Couldn't save: \(message)")
                .foregroundColor(.continuumError)
        }
    }
}

private struct ColorSwatchPicker: View {
    let title: String
    let colors: [(hex: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.continuumOnSurface)
            Spacer()
            HStack(spacing: 10) {
                ForEach(colors, id: \.hex) { color in
                    Button {
                        selection = color.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: color.hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(
                                        selection.caseInsensitiveCompare(color.hex) == .orderedSame
                                            ? Color.continuumOnSurface
                                            : Color.continuumSecondaryText.opacity(0.35),
                                        lineWidth: selection.caseInsensitiveCompare(color.hex) == .orderedSame ? 3 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.label)
                }
            }
        }
    }
}

// MARK: - Display helpers

private func qualityDisplayName(_ tag: String) -> String {
    ApplePlaybackQuality.displayNameWithBitrate(for: tag)
}

private func subtitleLanguageName(_ tag: String) -> String {
    if tag == PlaybackPrefSentinel.none || tag.isEmpty { return "None" }
    return PlaybackLanguageOption.label(forCode: tag)
}

#endif
