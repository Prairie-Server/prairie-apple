#if os(tvOS)
import SwiftUI

/// Native tvOS settings screen. Built on SwiftUI's `Form` with
/// `Toggle`, `Button`, and `.sheet(item:)`-driven pickers so tvOS draws
/// its own grouped chrome, chevrons, and focus platter — the same look
/// as Apple TV's Settings app.
///
/// **Why sheets instead of push.** `TVMainTabView` wraps a
/// sidebar-adaptive `TabView` in a single outer `NavigationStack` bound
/// to `router.path`. On tvOS 26, `NavigationLink` / `.pickerStyle(.navigationLink)`
/// pushes from inside a tab's `Form` don't reach that outer stack —
/// they either silently do nothing or queue behind the tab and only
/// appear when the user exits Settings. A local `NavigationStack`
/// doesn't capture them either. Presenting picker options via
/// `.sheet(item:)` bypasses the ambiguity: the option list appears
/// immediately as a modal, the user picks, the binding updates, the
/// sheet dismisses.
///
/// `FocusAwareLabel` / `FocusAwareAccountRow` flip each row's
/// foreground to `continuumBackground` on focus so the inherited
/// app-wide white `.tint` doesn't wash out text on the focus platter.
struct TVSettingsView: View {
    @State private var viewModel = TVSettingsViewModel()
    @State private var showSignOutConfirm = false
    @State private var activePicker: PickerKind?
    @Environment(AppRouter.self) private var router

    @State private var showCardOverlaysSheet = false

    var body: some View {
        Form {
            accountSection
            playbackSection
            subtitlesSection
            cardOverlaysSection
            librarySection
            accountActionsSection
            aboutSection
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showCardOverlaysSheet) {
            NavigationStack {
                TVCardOverlaySettingsView()
                    .navigationTitle("Card Overlays")
            }
        }
        .onChange(of: viewModel.editorSubtitleLanguage) { _, _ in
            Task { await viewModel.saveProfilePrefs() }
        }
        .onChange(of: viewModel.editorSubtitleMode) { _, _ in
            Task { await viewModel.saveProfilePrefs() }
        }
        .onChange(of: viewModel.editorShowForcedSubtitles) { _, _ in
            Task { await viewModel.saveProfilePrefs() }
        }
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                router.signOutAndReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be returned to the login screen.")
        }
        .sheet(item: $activePicker) { kind in
            pickerSheet(for: kind)
        }
    }

    // MARK: - Account header (tappable — switches profile)

    private var accountSection: some View {
        Section {
            Button(action: switchProfile) {
                FocusAwareAccountRow(
                    name: viewModel.displayName,
                    subtitle: viewModel.accountSubtitle,
                    avatar: viewModel.profileAvatar
                )
            }
        }
    }

    private func switchProfile() {
        AuthService.shared.profileId = nil
        router.showProfileSelection()
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section("Playback") {
            pickerRow(
                title: "Preferred Quality",
                options: Self.qualityOptions,
                selection: viewModel.preferredQuality,
                kind: .quality
            )

            pickerRow(
                title: "Audio Language",
                options: Self.audioLanguageOptions,
                selection: viewModel.preferredAudioLanguage,
                kind: .audioLanguage
            )

            focusAwareToggle("Profile 7 HDR10 Fallback", isOn: Binding(
                get: { viewModel.preferProfile7HDR10Fallback },
                set: { value in
                    viewModel.preferProfile7HDR10Fallback = value
                    Task { await viewModel.setPreferProfile7HDR10Fallback(value) }
                }
            ))

            focusAwareToggle("Auto-Play Next Episode", isOn: Binding(
                get: { viewModel.autoPlayNext },
                set: { value in
                    viewModel.autoPlayNext = value
                    Task { await viewModel.setAutoPlayNext(value) }
                }
            ))
            pickerRow(
                title: "Show Next Up",
                options: Self.nextUpPromptOptions,
                selection: String(viewModel.nextUpPromptSeconds),
                kind: .nextUpPrompt
            )
            focusAwareToggle("Skip Intros", isOn: Binding(
                get: { viewModel.skipIntros },
                set: { value in
                    viewModel.skipIntros = value
                    Task { await viewModel.setSkipIntros(value) }
                }
            ))
            focusAwareToggle("Skip Credits", isOn: Binding(
                get: { viewModel.skipCredits },
                set: { value in
                    viewModel.skipCredits = value
                    Task { await viewModel.setSkipCredits(value) }
                }
            ))

            Button(role: .destructive) {
                Task { await viewModel.resetPlaybackDeviceSettings() }
            } label: {
                FocusAwareRowLabel(title: "Reset Playback Overrides", isDestructive: true)
            }
        }
    }

    // MARK: - Subtitles

    private var subtitlesSection: some View {
        Section {
            pickerRow(
                title: "Language",
                options: Self.subtitleLanguageOptions,
                selection: viewModel.editorSubtitleLanguage,
                kind: .subtitleLanguage
            )

            pickerRow(
                title: "Behavior",
                options: Self.subtitleModeOptions,
                selection: viewModel.editorSubtitleMode,
                kind: .subtitleMode
            )

            focusAwareToggle("Show Forced Subtitles", isOn: forcedSubtitlesBinding)

            focusAwareToggle(
                "Use Device Appearance Override",
                isOn: Binding(
                    get: { viewModel.subtitleUsesDeviceAppearanceOverride },
                    set: { enabled in
                        Task { await viewModel.setSubtitleDeviceOverrideEnabled(enabled) }
                    }
                )
            )

            pickerRow(
                title: "Font Size",
                options: Self.subtitleSizeOptions,
                selection: viewModel.subtitleAppearance.fontSize.rawValue,
                kind: .subtitleSize
            )
            pickerRow(
                title: "Font Family",
                options: Self.fontFamilyOptions,
                selection: viewModel.subtitleAppearance.fontFamily.rawValue,
                kind: .subtitleFontFamily
            )
            pickerRow(
                title: "Font Color",
                options: Self.fontColorOptions,
                selection: viewModel.subtitleAppearance.fontColor.lowercased(),
                kind: .subtitleFontColor
            )
            focusAwareToggle("Text Outline", isOn: appearanceBoolBinding(\.textOutline))
            pickerRow(
                title: "Outline Color",
                options: Self.outlineColorOptions,
                selection: viewModel.subtitleAppearance.textOutlineColor.lowercased(),
                kind: .subtitleOutlineColor
            )
            pickerRow(
                title: "Background Style",
                options: Self.backgroundStyleOptions,
                selection: viewModel.subtitleAppearance.backgroundStyle.rawValue,
                kind: .subtitleBackgroundStyle
            )
            pickerRow(
                title: "Background Opacity",
                options: Self.backgroundOpacityOptions,
                selection: String(viewModel.subtitleAppearance.backgroundOpacity),
                kind: .subtitleBackgroundOpacity
            )
            pickerRow(
                title: "Background Color",
                options: Self.backgroundColorOptions,
                selection: viewModel.subtitleAppearance.backgroundColor.lowercased(),
                kind: .subtitleBackgroundColor
            )
            pickerRow(
                title: "Position",
                options: Self.positionOptions,
                selection: viewModel.subtitleAppearance.position.rawValue,
                kind: .subtitlePosition
            )
        } header: {
            Text("Subtitles")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.subtitleUsesDeviceAppearanceOverride
                     ? "Appearance is saved on the server for this profile on this Apple TV."
                     : "Appearance is using the server fallback for this profile on this Apple TV.")
                prefSaveFooter
            }
        }
    }

    @ViewBuilder
    private var prefSaveFooter: some View {
        if let state = viewModel.prefSaveState {
            switch state {
            case .saving:
                Text("Saving…")
            case .saved:
                Text("Saved")
            case .failed(let err):
                Text("Couldn't save: \(err)")
                    .foregroundStyle(.red)
            }
        } else {
            EmptyView()
        }
    }

    private var forcedSubtitlesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.editorShowForcedSubtitles == "on" },
            set: { viewModel.editorShowForcedSubtitles = $0 ? "on" : "off" }
        )
    }

    // MARK: - Card Overlays

    private var cardOverlaysSection: some View {
        Section("Card Overlays") {
            Button {
                showCardOverlaysSheet = true
            } label: {
                FocusAwareLabel(
                    title: "Customize Overlays",
                    systemImage: "rectangle.stack.badge.plus"
                )
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        Section("Library") {
            Button { router.navigate(to: .watchlist) } label: {
                FocusAwareLabel(title: "Watchlist", systemImage: "bookmark.fill")
            }
            Button { router.navigate(to: .favorites) } label: {
                FocusAwareLabel(title: "Favorites", systemImage: "heart.fill")
            }
            Button { router.navigate(to: .history) } label: {
                FocusAwareLabel(title: "Watch History", systemImage: "clock.fill")
            }
            Button { router.navigate(to: .collections) } label: {
                FocusAwareLabel(title: "Collections", systemImage: "square.stack.fill")
            }
        }
    }

    // MARK: - Account actions

    private var accountActionsSection: some View {
        Section("Account") {
            if viewModel.isAdmin {
                Button { router.navigate(to: .admin) } label: {
                    FocusAwareLabel(title: "Admin Dashboard", systemImage: "slider.horizontal.3")
                }
            }

            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                FocusAwareLabel(
                    title: "Sign Out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    isDestructive: true
                )
            }
        }
    }

    // MARK: - About / Server

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Server", value: viewModel.serverDisplayName.isEmpty
                ? "Not configured"
                : viewModel.serverDisplayName)

            if !viewModel.serverUrl.isEmpty,
               viewModel.serverDisplayName != viewModel.serverUrl {
                LabeledContent("URL", value: viewModel.serverUrl)
            }

            Button { router.navigate(to: .serverList) } label: {
                FocusAwareLabel(title: "Manage Servers", systemImage: "server.rack")
            }

            LabeledContent("Version", value: Self.appVersion)
        }
    }

    // MARK: - Rows

    /// `Toggle` with a focus-aware label so its title flips to a dark
    /// foreground on the white focus platter, matching the picker/button rows.
    private func focusAwareToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            FocusAwareRowLabel(title: title)
        }
    }

    private func pickerRow(
        title: String,
        options: [TVSettingsOption],
        selection: String,
        kind: PickerKind
    ) -> some View {
        let currentLabel = options.first(where: { $0.id == selection })?.label ?? "—"
        return Button { activePicker = kind } label: {
            FocusAwareValueRow(title: title, value: currentLabel)
        }
    }

    @ViewBuilder
    private func pickerSheet(for kind: PickerKind) -> some View {
        switch kind {
        case .quality:
            SettingsPickerSheet(
                title: "Preferred Quality",
                options: Self.qualityOptions,
                selection: Binding(
                    get: { viewModel.preferredQuality },
                    set: { value in
                        viewModel.preferredQuality = value
                        Task { await viewModel.setPreferredQuality(value) }
                    }
                )
            )
        case .audioLanguage:
            SettingsPickerSheet(
                title: "Audio Language",
                options: Self.audioLanguageOptions,
                selection: Binding(
                    get: { viewModel.preferredAudioLanguage },
                    set: { value in
                        viewModel.preferredAudioLanguage = value
                        Task { await viewModel.setPreferredAudioLanguage(value) }
                    }
                )
            )
        case .nextUpPrompt:
            SettingsPickerSheet(
                title: "Show Next Up",
                options: Self.nextUpPromptOptions,
                selection: Binding(
                    get: { String(viewModel.nextUpPromptSeconds) },
                    set: { value in
                        guard let seconds = Int(value) else { return }
                        viewModel.nextUpPromptSeconds = seconds
                        Task { await viewModel.setNextUpPromptSeconds(seconds) }
                    }
                )
            )
        case .subtitleLanguage:
            SettingsPickerSheet(
                title: "Language",
                options: Self.subtitleLanguageOptions,
                selection: $viewModel.editorSubtitleLanguage
            )
        case .subtitleMode:
            SettingsPickerSheet(
                title: "Behavior",
                options: Self.subtitleModeOptions,
                selection: $viewModel.editorSubtitleMode
            )
        case .subtitleSize:
            SettingsPickerSheet(
                title: "Font Size",
                options: Self.subtitleSizeOptions,
                selection: appearanceEnumBinding(\.fontSize, SubtitleFontSizePreset.self)
            )
        case .subtitleFontFamily:
            SettingsPickerSheet(
                title: "Font Family",
                options: Self.fontFamilyOptions,
                selection: appearanceEnumBinding(\.fontFamily, SubtitleFontFamilyPreset.self),
                subtitlePreviewAppearance: viewModel.subtitleAppearance
            )
        case .subtitleFontColor:
            SettingsPickerSheet(
                title: "Font Color",
                options: Self.fontColorOptions,
                selection: appearanceStringBinding(\.fontColor)
            )
        case .subtitleOutlineColor:
            SettingsPickerSheet(
                title: "Outline Color",
                options: Self.outlineColorOptions,
                selection: appearanceStringBinding(\.textOutlineColor)
            )
        case .subtitleBackgroundStyle:
            SettingsPickerSheet(
                title: "Background Style",
                options: Self.backgroundStyleOptions,
                selection: appearanceEnumBinding(\.backgroundStyle, SubtitleBackgroundStylePreset.self)
            )
        case .subtitleBackgroundOpacity:
            SettingsPickerSheet(
                title: "Background Opacity",
                options: Self.backgroundOpacityOptions,
                selection: appearanceIntBinding(\.backgroundOpacity)
            )
        case .subtitleBackgroundColor:
            SettingsPickerSheet(
                title: "Background Color",
                options: Self.backgroundColorOptions,
                selection: appearanceStringBinding(\.backgroundColor)
            )
        case .subtitlePosition:
            SettingsPickerSheet(
                title: "Position",
                options: Self.positionOptions,
                selection: appearanceEnumBinding(\.position, SubtitlePositionPreset.self)
            )
        }
    }

    private func appearanceStringBinding(_ keyPath: WritableKeyPath<SubtitleAppearance, String>) -> Binding<String> {
        Binding(
            get: { viewModel.subtitleAppearance[keyPath: keyPath].lowercased() },
            set: { value in
                var next = viewModel.subtitleAppearance
                next[keyPath: keyPath] = value
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    private func appearanceIntBinding(_ keyPath: WritableKeyPath<SubtitleAppearance, Int>) -> Binding<String> {
        Binding(
            get: { String(viewModel.subtitleAppearance[keyPath: keyPath]) },
            set: { value in
                guard let intValue = Int(value) else { return }
                var next = viewModel.subtitleAppearance
                next[keyPath: keyPath] = intValue
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    private func appearanceBoolBinding(_ keyPath: WritableKeyPath<SubtitleAppearance, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel.subtitleAppearance[keyPath: keyPath] },
            set: { value in
                var next = viewModel.subtitleAppearance
                next[keyPath: keyPath] = value
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    private func appearanceEnumBinding<Value>(
        _ keyPath: WritableKeyPath<SubtitleAppearance, Value>,
        _ type: Value.Type
    ) -> Binding<String> where Value: RawRepresentable, Value.RawValue == String {
        Binding(
            get: { viewModel.subtitleAppearance[keyPath: keyPath].rawValue },
            set: { rawValue in
                guard let value = Value(rawValue: rawValue) else { return }
                var next = viewModel.subtitleAppearance
                next[keyPath: keyPath] = value
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    // MARK: - Option sets

    fileprivate static let qualityOptions: [TVSettingsOption] =
        ApplePlaybackQuality.settingsOptions.map { option in
            .init(id: option.id, label: option.labelWithBitrate)
        }

    fileprivate static let audioLanguageOptions: [TVSettingsOption] = [
        .init(id: "", label: "Default"),
        .init(id: "en", label: "English"),
        .init(id: "es", label: "Spanish"),
        .init(id: "fr", label: "French"),
        .init(id: "de", label: "German"),
        .init(id: "it", label: "Italian"),
        .init(id: "pt", label: "Portuguese"),
        .init(id: "ja", label: "Japanese"),
        .init(id: "ko", label: "Korean"),
    ]

    fileprivate static let nextUpPromptOptions: [TVSettingsOption] = [
        .init(id: "0", label: "At end"),
        .init(id: "10", label: "10 seconds before end"),
        .init(id: "30", label: "30 seconds before end"),
        .init(id: "60", label: "1 minute before end"),
        .init(id: "120", label: "2 minutes before end"),
    ]

    fileprivate static let subtitleLanguageOptions: [TVSettingsOption] =
        [.init(id: PlaybackPrefSentinel.none, label: "None")]
            + PlaybackLanguageOption.all.map { .init(id: $0.code, label: $0.label) }

    fileprivate static let subtitleModeOptions: [TVSettingsOption] =
        SubtitleMode.allCases.map { .init(id: $0.rawValue, label: $0.displayLabel) }

    fileprivate static let subtitleSizeOptions: [TVSettingsOption] = [
        .init(id: "small",   label: "Small"),
        .init(id: "medium",  label: "Medium"),
        .init(id: "large",   label: "Large"),
        .init(id: "xlarge",  label: "X-Large"),
        .init(id: "xxlarge", label: "XX-Large"),
    ]

    fileprivate static let fontFamilyOptions: [TVSettingsOption] =
        SubtitleFontFamilyPreset.allCases.map {
            .init(id: $0.rawValue, label: $0.label, previewFontName: $0.assFontName)
        }

    fileprivate static let fontColorOptions: [TVSettingsOption] =
        SubtitleAppearance.fontColors.map { .init(id: $0.hex, label: $0.label) }

    fileprivate static let outlineColorOptions: [TVSettingsOption] =
        SubtitleAppearance.outlineColors.map { .init(id: $0.hex, label: $0.label) }

    fileprivate static let backgroundStyleOptions: [TVSettingsOption] =
        SubtitleBackgroundStylePreset.allCases.map { .init(id: $0.rawValue, label: $0.label) }

    fileprivate static let backgroundOpacityOptions: [TVSettingsOption] =
        stride(from: 0, through: 100, by: 5).map { .init(id: String($0), label: "\($0)%") }

    fileprivate static let backgroundColorOptions: [TVSettingsOption] =
        SubtitleAppearance.backgroundColors.map { .init(id: $0.hex, label: $0.label) }

    fileprivate static let positionOptions: [TVSettingsOption] =
        SubtitlePositionPreset.allCases.map { .init(id: $0.rawValue, label: $0.label) }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Picker identity

    enum PickerKind: String, Identifiable, Hashable {
        case quality
        case audioLanguage
        case nextUpPrompt
        case subtitleLanguage
        case subtitleMode
        case subtitleSize
        case subtitleFontFamily
        case subtitleFontColor
        case subtitleOutlineColor
        case subtitleBackgroundStyle
        case subtitleBackgroundOpacity
        case subtitleBackgroundColor
        case subtitlePosition

        var id: String { rawValue }
    }
}

// MARK: - Shared picker types

/// Option model shared by the picker row and its sheet.
struct TVSettingsOption: Identifiable, Hashable {
    let id: String
    let label: String
    var previewFontName: String? = nil
}

/// Modal picker presented by `.sheet(item:)`. Contains its own `Form`
/// and `NavigationStack` so the sheet has a title + Cancel affordance
/// regardless of where it was presented from.
private struct SettingsPickerSheet: View {
    let title: String
    let options: [TVSettingsOption]
    @Binding var selection: String
    var subtitlePreviewAppearance: SubtitleAppearance? = nil

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedOptionID: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let subtitlePreviewAppearance {
                    SettingsSubtitlePreview(
                        appearance: previewAppearance(from: subtitlePreviewAppearance),
                        text: "This is how subtitles will look."
                    )
                }

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: options.count > 8) {
                        LazyVStack(spacing: 10) {
                            ForEach(options) { option in
                                SettingsPickerOptionRow(
                                    option: option,
                                    isSelected: option.id == selection,
                                    focusedOptionID: $focusedOptionID
                                ) {
                                    selection = option.id
                                    dismiss()
                                }
                                .id(option.id)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onAppear {
                        focusSelection()
                        scrollToFocusedOption(with: proxy, animated: false)
                    }
                    .onChange(of: focusedOptionID) { _, _ in
                        scrollToFocusedOption(with: proxy)
                    }
                    .onChange(of: selection) { _, _ in
                        scrollToFocusedOption(with: proxy)
                    }
                }
            }
            .navigationTitle(title)
            .safeAreaPadding(.horizontal, ContinuumTheme.safePadding)
            .safeAreaPadding(.vertical, ContinuumTheme.safePadding / 2)
        }
        .focusSection()
        .onChange(of: focusedOptionID) { _, value in
            if value == nil {
                focusSelection()
            }
        }
    }

    private func focusSelection() {
        focusedOptionID = options.first { $0.id == selection }?.id ?? options.first?.id
    }

    private func previewAppearance(from base: SubtitleAppearance) -> SubtitleAppearance {
        let previewID = focusedOptionID ?? selection
        guard let fontFamily = SubtitleFontFamilyPreset(rawValue: previewID) else {
            return base
        }
        var copy = base
        copy.fontFamily = fontFamily
        return copy
    }

    private func scrollToFocusedOption(with proxy: ScrollViewProxy, animated: Bool = true) {
        let targetID = focusedOptionID ?? options.first { $0.id == selection }?.id ?? options.first?.id
        guard let targetID else { return }
        if animated {
            withAnimation(.easeOut(duration: ContinuumTheme.fastDuration)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }
}

private struct SettingsPickerOptionRow: View {
    let option: TVSettingsOption
    let isSelected: Bool
    @FocusState.Binding var focusedOptionID: String?
    let onSelect: () -> Void

    private var isFocused: Bool { focusedOptionID == option.id }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(option.label)
                    .font(.system(size: 30, weight: .medium))
                    .lineLimit(1)

                if let previewFontName = option.previewFontName {
                    Text("Subtitle sample")
                        .font(.custom(previewFontName, size: 22))
                        .lineLimit(1)
                        .opacity(0.72)
                }
            }
            .foregroundStyle(isFocused ? Color.continuumBackground : .continuumOnSurface)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.continuumBackground : .continuumOnSurface)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? Color.white : Color.continuumSurfaceElevated.opacity(0.74))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .focusable(true)
        .focused($focusedOptionID, equals: option.id)
        .onTapGesture(perform: onSelect)
        .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(option.label)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

private struct SettingsSubtitlePreview: View {
    let appearance: SubtitleAppearance
    let text: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.72))
            Text(text)
                .font(.custom(appearance.fontFamily.assFontName, size: 34))
                .foregroundStyle(Color(hex: appearance.fontColor))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
                .background(background)
                .overlay(outline)
                .shadow(
                    color: appearance.backgroundStyle == .shadow ? .black.opacity(0.72) : .clear,
                    radius: 2,
                    x: 0,
                    y: 2
                )
        }
        .frame(height: 150)
        .accessibilityLabel("Subtitle preview")
        .accessibilityValue(text)
    }

    @ViewBuilder
    private var background: some View {
        if appearance.backgroundStyle == .box {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: appearance.backgroundColor)
                    .opacity(Double(appearance.backgroundOpacity) / 100.0))
        }
    }

    @ViewBuilder
    private var outline: some View {
        if appearance.textOutline || appearance.backgroundStyle == .outline {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: appearance.textOutlineColor), lineWidth: 2)
        }
    }
}

// MARK: - Focus-aware row primitives

/// Label-style row (icon + title) that flips to a dark foreground when
/// the enclosing Button gains focus. Used for every button row in the
/// Form so text stays legible against the light focus platter.
private struct FocusAwareLabel: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(foreground)
    }

    private var foreground: Color {
        if isFocused { return .continuumBackground }
        return isDestructive ? .continuumError : .continuumOnSurface
    }
}

/// Title + trailing value row for picker rows. Flips both pieces to a dark
/// foreground on focus — like `FocusAwareLabel` — so the value rows match the
/// button rows instead of inheriting the washed-out app-wide white tint on the
/// focus platter.
private struct FocusAwareValueRow: View {
    let title: String
    let value: String

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        LabeledContent {
            Text(value).foregroundStyle(valueColor)
        } label: {
            Text(title).foregroundStyle(titleColor)
        }
    }

    private var titleColor: Color {
        isFocused ? .continuumBackground : .continuumOnSurface
    }

    private var valueColor: Color {
        (isFocused ? Color.continuumBackground : Color.continuumOnSurface).opacity(0.6)
    }
}

/// Focus-aware text label for icon-less Form rows (`Toggle`s and plain-text
/// action buttons like "Reset Playback Overrides"). The label sits inside the
/// focusable row, so `\.isFocused` flips it dark on the focus platter —
/// matching every other row's contrast, including destructive rows which flip
/// from red to the dark platter color exactly like `FocusAwareLabel`.
private struct FocusAwareRowLabel: View {
    let title: String
    var isDestructive: Bool = false

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .foregroundStyle(foreground)
    }

    private var foreground: Color {
        if isFocused { return .continuumBackground }
        return isDestructive ? .continuumError : .continuumOnSurface
    }
}

/// Tappable account row at the top of Settings. Switches profile on
/// activation and flips foreground colors on focus like every other
/// row in the Form.
private struct FocusAwareAccountRow: View {
    let name: String
    let subtitle: String
    let avatar: String?

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 20) {
            ProfileAvatarView(
                avatar: avatar,
                name: name,
                size: 72,
                backgroundColor: isFocused
                    ? Color.continuumBackground.opacity(0.15)
                    : .continuumSurfaceElevated,
                textColor: isFocused ? .continuumBackground : .continuumOnSurface
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(primaryColor)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(secondaryColor)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(secondaryColor)
        }
        .padding(.vertical, 4)
    }

    private var primaryColor: Color {
        isFocused ? .continuumBackground : .continuumOnSurface
    }

    private var secondaryColor: Color {
        (isFocused ? Color.continuumBackground : Color.continuumOnSurface).opacity(0.6)
    }
}
#endif
