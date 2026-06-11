#if os(tvOS)
import SwiftUI

/// Playback sub-screen of tvOS Settings, presented as a full-screen
/// cover from the root menu (push navigation inside the tab's `Form`
/// is unreliable on tvOS 26 — see `TVSettingsView`). Option pickers
/// are nested full-screen covers.
struct TVPlaybackSettingsView: View {
    @Bindable var viewModel: TVSettingsViewModel
    @State private var activePicker: PickerKind?

    var body: some View {
        NavigationStack {
            Form {
                streamingSection
                episodesSection
                resetSection
            }
            .navigationTitle("Playback")
            .background(Color.continuumBackground.ignoresSafeArea())
        }
        .fullScreenCover(item: $activePicker) { kind in
            pickerSheet(for: kind)
        }
    }

    // MARK: - Sections

    private var streamingSection: some View {
        Section {
            Button { activePicker = .quality } label: {
                FocusAwareValueRow(
                    title: "Quality",
                    value: TVSettingsOptions.label(for: viewModel.preferredQuality, in: TVSettingsOptions.quality)
                )
            }

            Button { activePicker = .audioLanguage } label: {
                FocusAwareValueRow(
                    title: "Audio Language",
                    value: TVSettingsOptions.label(for: viewModel.preferredAudioLanguage, in: TVSettingsOptions.audioLanguage)
                )
            }

            Toggle(isOn: Binding(
                get: { viewModel.preferProfile7HDR10Fallback },
                set: { value in
                    viewModel.preferProfile7HDR10Fallback = value
                    Task { await viewModel.setPreferProfile7HDR10Fallback(value) }
                }
            )) {
                FocusAwareRowLabel(title: "Profile 7 HDR10 Fallback")
            }
        } header: {
            Text("Streaming")
        } footer: {
            Text("The fallback plays Dolby Vision Profile 7 as HDR10 on this Apple TV.")
        }
    }

    private var episodesSection: some View {
        Section("Episodes") {
            Toggle(isOn: Binding(
                get: { viewModel.autoPlayNext },
                set: { value in
                    viewModel.autoPlayNext = value
                    Task { await viewModel.setAutoPlayNext(value) }
                }
            )) {
                FocusAwareRowLabel(title: "Auto-Play Next Episode")
            }

            Button { activePicker = .nextUpPrompt } label: {
                FocusAwareValueRow(
                    title: "Show Next Up",
                    value: TVSettingsOptions.label(for: String(viewModel.nextUpPromptSeconds), in: TVSettingsOptions.nextUpPrompt)
                )
            }

            Toggle(isOn: Binding(
                get: { viewModel.skipIntros },
                set: { value in
                    viewModel.skipIntros = value
                    Task { await viewModel.setSkipIntros(value) }
                }
            )) {
                FocusAwareRowLabel(title: "Skip Intros")
            }

            Toggle(isOn: Binding(
                get: { viewModel.skipCredits },
                set: { value in
                    viewModel.skipCredits = value
                    Task { await viewModel.setSkipCredits(value) }
                }
            )) {
                FocusAwareRowLabel(title: "Skip Credits")
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                Task { await viewModel.resetPlaybackDeviceSettings() }
            } label: {
                FocusAwareRowLabel(title: "Reset Playback Overrides", isDestructive: true)
            }
        } footer: {
            Text("Resets playback choices for this Apple TV and profile back to the server fallback.")
        }
    }

    // MARK: - Pickers

    @ViewBuilder
    private func pickerSheet(for kind: PickerKind) -> some View {
        switch kind {
        case .quality:
            TVSettingsPickerSheet(
                title: "Quality",
                options: TVSettingsOptions.quality,
                selection: Binding(
                    get: { viewModel.preferredQuality },
                    set: { value in
                        viewModel.preferredQuality = value
                        Task { await viewModel.setPreferredQuality(value) }
                    }
                )
            )
        case .audioLanguage:
            TVSettingsPickerSheet(
                title: "Audio Language",
                options: TVSettingsOptions.audioLanguage,
                selection: Binding(
                    get: { viewModel.preferredAudioLanguage },
                    set: { value in
                        viewModel.preferredAudioLanguage = value
                        Task { await viewModel.setPreferredAudioLanguage(value) }
                    }
                )
            )
        case .nextUpPrompt:
            TVSettingsPickerSheet(
                title: "Show Next Up",
                options: TVSettingsOptions.nextUpPrompt,
                selection: Binding(
                    get: { String(viewModel.nextUpPromptSeconds) },
                    set: { value in
                        guard let seconds = Int(value) else { return }
                        viewModel.nextUpPromptSeconds = seconds
                        Task { await viewModel.setNextUpPromptSeconds(seconds) }
                    }
                )
            )
        }
    }

    enum PickerKind: String, Identifiable {
        case quality
        case audioLanguage
        case nextUpPrompt

        var id: String { rawValue }
    }
}
#endif
