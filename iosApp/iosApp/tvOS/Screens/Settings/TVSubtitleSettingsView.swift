#if os(tvOS)
import SwiftUI

/// Subtitles pane of tvOS Settings, rendered inline in the right pane of
/// the two-pane `TVSettingsView`. Profile-wide prefs (language / behavior
/// / forced) save through the root view's `onChange` handlers; the
/// appearance block writes a per-device override directly.
struct TVSubtitleSettingsPane: View {
    @Bindable var viewModel: TVSettingsViewModel
    @State private var activePicker: PickerKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            profileSection
            if AICapabilities.shared.metadataEnabled {
                metadataLanguageSection
            }
            appearanceSection
        }
        .fullScreenCover(item: $activePicker) { kind in
            pickerSheet(for: kind)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var profileSection: some View {
        TVSettingsSectionHeader("PROFILE")

        TVSettingsPickerRow(
            title: "Language",
            value: TVSettingsOptions.label(for: viewModel.editorSubtitleLanguage, in: TVSettingsOptions.subtitleLanguage)
        ) { activePicker = .language }

        TVSettingsPickerRow(
            title: "Behavior",
            value: TVSettingsOptions.label(for: viewModel.editorSubtitleMode, in: TVSettingsOptions.subtitleMode)
        ) { activePicker = .mode }

        TVSettingsToggleRow(
            title: "Show Forced Subtitles",
            isOn: viewModel.editorShowForcedSubtitles == "on"
        ) {
            viewModel.editorShowForcedSubtitles =
                viewModel.editorShowForcedSubtitles == "on" ? "off" : "on"
        }

        TVSettingsFooter("Used to pick a matching track when one is available. Forced subtitles cover foreign-language dialogue even when subtitles are off or set to auto.")
        prefSaveFooter
    }

    @ViewBuilder
    private var metadataLanguageSection: some View {
        TVSettingsSectionHeader("METADATA")

        TVSettingsPickerRow(
            title: "Metadata Language",
            value: TVSettingsOptions.label(for: viewModel.editorPreferredMetadataLanguage, in: TVSettingsOptions.metadataLanguage)
        ) { activePicker = .metadataLanguage }

        TVSettingsFooter("Translates descriptions and taglines into your preferred language when available. Titles are never translated.")
    }

    @ViewBuilder
    private var appearanceSection: some View {
        TVSettingsSectionHeader("APPEARANCE")

        TVSettingsToggleRow(
            title: "Custom Appearance",
            isOn: viewModel.subtitleUsesDeviceAppearanceOverride
        ) {
            let enabled = !viewModel.subtitleUsesDeviceAppearanceOverride
            Task { await viewModel.setSubtitleDeviceOverrideEnabled(enabled) }
        }

        pickerRow("Font Size", options: TVSettingsOptions.subtitleSize,
                  selection: viewModel.subtitleAppearance.fontSize.rawValue, kind: .fontSize)
        pickerRow("Font Family", options: TVSettingsOptions.fontFamily,
                  selection: viewModel.subtitleAppearance.fontFamily.rawValue, kind: .fontFamily)
        pickerRow("Font Color", options: TVSettingsOptions.fontColor,
                  selection: viewModel.subtitleAppearance.fontColor.lowercased(), kind: .fontColor)

        TVSettingsToggleRow(
            title: "Text Outline",
            isOn: viewModel.subtitleAppearance.textOutline
        ) {
            var next = viewModel.subtitleAppearance
            next.textOutline.toggle()
            Task { await viewModel.setSubtitleAppearance(next) }
        }

        pickerRow("Outline Color", options: TVSettingsOptions.outlineColor,
                  selection: viewModel.subtitleAppearance.textOutlineColor.lowercased(), kind: .outlineColor)
        pickerRow("Background Style", options: TVSettingsOptions.backgroundStyle,
                  selection: viewModel.subtitleAppearance.backgroundStyle.rawValue, kind: .backgroundStyle)
        pickerRow("Background Opacity", options: TVSettingsOptions.backgroundOpacity,
                  selection: String(viewModel.subtitleAppearance.backgroundOpacity), kind: .backgroundOpacity)
        pickerRow("Background Color", options: TVSettingsOptions.backgroundColor,
                  selection: viewModel.subtitleAppearance.backgroundColor.lowercased(), kind: .backgroundColor)
        pickerRow("Position", options: TVSettingsOptions.position,
                  selection: viewModel.subtitleAppearance.position.rawValue, kind: .position)

        TVSettingsFooter(viewModel.subtitleUsesDeviceAppearanceOverride
            ? "Appearance is saved on the server for this profile on this Apple TV."
            : "Appearance is using the server fallback for this profile on this Apple TV.")
    }

    @ViewBuilder
    private var prefSaveFooter: some View {
        if let state = viewModel.prefSaveState {
            switch state {
            case .saving:
                TVSettingsFooter("Saving…")
            case .saved:
                TVSettingsFooter("Saved")
            case .failed(let err):
                Text("Couldn't save: \(err)")
                    .font(.system(size: 19))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Rows

    private func pickerRow(
        _ title: String,
        options: [TVSettingsOption],
        selection: String,
        kind: PickerKind
    ) -> some View {
        TVSettingsPickerRow(
            title: title,
            value: TVSettingsOptions.label(for: selection, in: options)
        ) { activePicker = kind }
    }

    // MARK: - Pickers

    @ViewBuilder
    private func pickerSheet(for kind: PickerKind) -> some View {
        switch kind {
        case .language:
            TVSettingsPickerSheet(
                title: "Language",
                options: TVSettingsOptions.subtitleLanguage,
                selection: $viewModel.editorSubtitleLanguage
            )
        case .mode:
            TVSettingsPickerSheet(
                title: "Behavior",
                options: TVSettingsOptions.subtitleMode,
                selection: $viewModel.editorSubtitleMode
            )
        case .metadataLanguage:
            TVSettingsPickerSheet(
                title: "Metadata Language",
                options: TVSettingsOptions.metadataLanguage,
                selection: $viewModel.editorPreferredMetadataLanguage
            )
        case .fontSize:
            TVSettingsPickerSheet(
                title: "Font Size",
                options: TVSettingsOptions.subtitleSize,
                selection: appearanceEnumBinding(\.fontSize, SubtitleFontSizePreset.self)
            )
        case .fontFamily:
            TVSettingsPickerSheet(
                title: "Font Family",
                options: TVSettingsOptions.fontFamily,
                selection: appearanceEnumBinding(\.fontFamily, SubtitleFontFamilyPreset.self),
                subtitlePreviewAppearance: viewModel.subtitleAppearance
            )
        case .fontColor:
            TVSettingsPickerSheet(
                title: "Font Color",
                options: TVSettingsOptions.fontColor,
                selection: appearanceStringBinding(\.fontColor)
            )
        case .outlineColor:
            TVSettingsPickerSheet(
                title: "Outline Color",
                options: TVSettingsOptions.outlineColor,
                selection: appearanceStringBinding(\.textOutlineColor)
            )
        case .backgroundStyle:
            TVSettingsPickerSheet(
                title: "Background Style",
                options: TVSettingsOptions.backgroundStyle,
                selection: appearanceEnumBinding(\.backgroundStyle, SubtitleBackgroundStylePreset.self)
            )
        case .backgroundOpacity:
            TVSettingsPickerSheet(
                title: "Background Opacity",
                options: TVSettingsOptions.backgroundOpacity,
                selection: appearanceIntBinding(\.backgroundOpacity)
            )
        case .backgroundColor:
            TVSettingsPickerSheet(
                title: "Background Color",
                options: TVSettingsOptions.backgroundColor,
                selection: appearanceStringBinding(\.backgroundColor)
            )
        case .position:
            TVSettingsPickerSheet(
                title: "Position",
                options: TVSettingsOptions.position,
                selection: appearanceEnumBinding(\.position, SubtitlePositionPreset.self)
            )
        }
    }

    enum PickerKind: String, Identifiable {
        case language
        case mode
        case metadataLanguage
        case fontSize
        case fontFamily
        case fontColor
        case outlineColor
        case backgroundStyle
        case backgroundOpacity
        case backgroundColor
        case position

        var id: String { rawValue }
    }

    // MARK: - Appearance bindings

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
}
#endif
