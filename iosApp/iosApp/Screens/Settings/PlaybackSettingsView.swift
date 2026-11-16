#if !os(tvOS)
import SwiftUI

/// Playback preferences sub-screen — a native grouped list in the
/// style of the iOS Settings app: plain rows, navigation-link pickers,
/// and footers for the fine print.
struct PlaybackSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var spoilers = EpisodeSpoilerPreferences.shared
    @State private var showUseProfileSettingsConfirmation = false

    /// The app language, so a switch re-renders the labels.
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            if viewModel.hasHeldPlaybackChanges {
                HeldSettingChangesSection(
                    retry: { await viewModel.retryHeldPlaybackChanges() },
                    discard: { await viewModel.discardHeldPlaybackChanges() },
                    message: viewModel.heldPlaybackChangesMessage
                )
            }
            if viewModel.playbackChangeWasRejected {
                rejectedChangeSection
            }
            qualitySection
            #if os(iOS)
            cellularQualitySection
            #endif
            if viewModel.showsConnectionGroup {
                connectionSection
            }
            streamingSection
            behaviorSection
            // Hidden entirely on servers that do not serve the two keys.
            if spoilers.showsSettings {
                EpisodeSpoilerSettingsSection(store: spoilers)
            }
            SeekIntervalSettingsSections()
            resetSection
        }
        .task { await spoilers.refresh() }
        // Reloads on another network, whose speed and limit differ.
        .task(id: BandwidthProbeScheduler.shared.connectionRevision) { await viewModel.loadPlaybackConnection() }
        .settingsListChrome()
        .navigationTitle(Text(.settingsPlayback))
        .prairieNavigationTitleDisplayMode(.inline)
        .prairieToolbarColorSchemeDark()
        .alert(
            Text(SettingsViewModel.useProfileSettingsTitle),
            isPresented: $showUseProfileSettingsConfirmation
        ) {
            Button(.settingsProfileSettingsUseAll, role: .destructive) {
                Task { await viewModel.resetPlaybackDeviceSettings() }
            }
            Button(.commonCancel, role: .cancel) {}
        } message: {
            Text(verbatim: viewModel.useProfileSettingsMessage)
        }
    }

    // MARK: - Quality

    /// Resolution and bitrate are two pickers: someone may want only 1080p on
    /// a fast connection, and a 1080p file can carry a higher bitrate than a
    /// 4K one. Each writes and clears only its own setting, as on the web.
    private var qualitySection: some View {
        Section {
            choiceRow(.settingsControlResolution, .resolution, value: .verbatim(viewModel.qualityResolutionLabel), options: resolutionChoices)

            choiceRow(.settingsControlBitrate, .maxBitrate, value: viewModel.maxBitrateLabel, options: maxBitrateChoices)

            // Three-way (labels fixed by the contract).
            if viewModel.showsBufferingQualityMode {
                choiceRow(
                    SettingsViewModel.bufferingQualityTitle,
                    .bufferingQualityMode,
                    value: .verbatim(viewModel.bufferingQualityMode.label),
                    options: BufferingQualityMode.allCases.map { SettingsChoice(id: $0.wireValue, label: .verbatim($0.label)) }
                )
            }

            // The sentence wraps, so Reset takes its own row rather than
            // sitting under it inside the same cell.
            if let limit = viewModel.learnedConnectionLimitText {
                Text(verbatim: limit)
                    .foregroundStyle(Color.prairieOnSurface)
                Button(.settingsLearnedLimitReset) {
                    Task { await viewModel.resetLearnedConnectionLimit() }
                }
            }
        } header: {
            Text(.settingsSectionQuality)
                .foregroundStyle(Color.prairieSecondaryText)
        } footer: {
            Text(verbatim: qualityFooterText)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .listRowBackground(Color.prairieGroupedCell)
    }

    /// The quality note, the buffering description, then a failed Reset, one
    /// line each.
    private var qualityFooterText: String {
        var lines = [viewModel.qualityFooterText]
        if viewModel.showsBufferingQualityMode {
            lines.append(AppLanguage.string(SettingsViewModel.bufferingQualityDescription, locale: locale))
        }
        if let error = viewModel.learnedLimitResetError {
            lines.append(AppLanguage.string(error, locale: locale))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Connection

    /// The speed the bandwidth probe measured on this connection, a test on
    /// demand, and what Auto plays as-is at that speed.
    private var connectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(SettingsViewModel.connectionSpeedTitle)
                    .foregroundStyle(Color.prairieOnSurface)
                // "measured 3 minutes ago" moves on while the page is open.
                TimelineView(.everyMinute) { context in
                    Text(verbatim: viewModel.connectionSpeedLine(at: context.date))
                        .font(.footnote)
                        .foregroundStyle(Color.prairieSecondaryText)
                }
            }
            if viewModel.connectionSpeedSkippedText == nil {
                Button {
                    Task { await viewModel.testConnectionSpeed() }
                } label: {
                    Text(viewModel.isTestingConnectionSpeed
                         ? SettingsViewModel.testingSpeedLabel
                         : SettingsViewModel.testSpeedAction)
                }
                .disabled(viewModel.isTestingConnectionSpeed)
            }
        } header: {
            Text(SettingsViewModel.connectionSectionTitle)
                .foregroundStyle(Color.prairieSecondaryText)
        } footer: {
            if let footer = connectionFooterText {
                Text(verbatim: footer)
                    .foregroundStyle(Color.prairieSecondaryText)
            }
        }
        .listRowBackground(Color.prairieGroupedCell)
    }

    /// The budget, then the last test's answer, one line each.
    private var connectionFooterText: String? {
        let message = viewModel.connectionSpeedMessage.map { AppLanguage.string($0, locale: locale) }
        let lines = [viewModel.autoBudgetText, message].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    #if os(iOS)
    /// iPhone and iPad only. One preset list, since bitrate is what matters
    /// on a data plan.
    private var cellularQualitySection: some View {
        Section {
            choiceRow(
                .settingsPlaybackCellularQuality,
                .cellularQuality,
                value: .verbatim(viewModel.cellularQualityLabel),
                options: cellularQualityChoices
            )
        } footer: {
            Text(SettingsViewModel.cellularQualityFooterText)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .listRowBackground(Color.prairieGroupedCell)
    }
    #endif

    // MARK: - Streaming

    private var streamingSection: some View {
        Section {
            choiceRow(.settingsControlAudioLanguage, .audioLanguage, value: .verbatim(audioLanguageLabel), options: audioLanguageChoices)

            Toggle(.settingsManifestPlayerHdrEnabledLabel, isOn: $viewModel.hdrEnabled)
                .foregroundStyle(Color.prairieOnSurface)
                .tint(.prairieSwitchOn)

            Toggle(.settingsManifestPlayerDolbyVisionEnabledLabel, isOn: $viewModel.dolbyVisionEnabled)
                .foregroundStyle(Color.prairieOnSurface)
                .tint(.prairieSwitchOn)
                .disabled(!viewModel.hdrEnabled)

            Toggle(.settingsPlaybackSeekCache, isOn: $viewModel.seekCacheEnabled)
                .foregroundStyle(Color.prairieOnSurface)
                .tint(.prairieSwitchOn)

            Picker(.settingsPlaybackBufferAhead, selection: $viewModel.bufferAhead) {
                ForEach(BufferAheadMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .foregroundStyle(Color.prairieOnSurface)
            .settingsPickerStyle()

            Toggle(.settingsPlaybackLosslessAudio, isOn: $viewModel.losslessAudioEnabled)
                .foregroundStyle(Color.prairieOnSurface)
                .tint(.prairieSwitchOn)

            if AetherObjectAudioPolicy.isAvailable {
                Toggle(.settingsPlaybackTrueHdAtmos, isOn: $viewModel.trueHDAtmosEnabled)
                    .foregroundStyle(Color.prairieOnSurface)
                    .tint(.prairieSwitchOn)
            }

            Picker(.settingsPlaybackDeinterlacing, selection: $viewModel.deinterlaceMode) {
                ForEach(DeinterlacePreference.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .foregroundStyle(Color.prairieOnSurface)
            .settingsPickerStyle()

            Picker(.settingsPlaybackDeinterlacingFieldRate, selection: $viewModel.deinterlaceFieldRate) {
                ForEach(DeinterlaceFieldRatePreference.allCases, id: \.self) { rate in
                    Text(rate.label).tag(rate)
                }
            }
            .foregroundStyle(Color.prairieOnSurface)
            .settingsPickerStyle()

            // iOS only: the engine's background policy is driven by the app
            // lifecycle notifications, which macOS does not post — a toggle
            // there would control nothing.
            #if os(iOS)
            Toggle(.settingsPlaybackBackgroundPlayback, isOn: $viewModel.backgroundPlaybackEnabled)
                .foregroundStyle(Color.prairieOnSurface)
                .tint(.prairieSwitchOn)
            #endif
        } header: {
            Text(.settingsSectionStreaming)
                .foregroundStyle(Color.prairieSecondaryText)
        } footer: {
            Text(verbatim: streamingFooterText)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .listRowBackground(Color.prairieGroupedCell)
    }

    private var streamingFooterText: String {
        var text = SettingsViewModel.hdrFooterText
        text += " " + AppLanguage.string(.settingsPlaybackSurroundFooter, locale: locale)
        if AetherObjectAudioPolicy.isAvailable {
            text += " " + AppLanguage.string(.settingsPlaybackAtmosFooter, locale: locale)
        }
        return text
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        Section {
            // On / Off choices rather than switches: a switch has no third
            // position for going back to the profile's choice.
            choiceRow(
                .settingsControlAutoplay,
                .autoPlayNext,
                value: viewModel.autoPlayNext ? .settingsOn : .settingsOff,
                options: onOffChoices
            )

            // The Mac player has no Next Up screen, so the limit does not apply there.
            #if !os(macOS)
            // Client-local, so there is no profile value to go back to.
            SettingsChoiceRow(
                title: .settingsManifestPlayerPassoutThresholdLabel,
                value: SettingsViewModel.stillWatchingLabel(viewModel.stillWatchingThreshold),
                options: SettingsViewModel.stillWatchingChoices.map { SettingsChoice(id: $0.id, label: $0.label) },
                selection: $viewModel.stillWatchingSelection
            )
            #endif

            choiceRow(
                .settingsNextUpTitle,
                .nextUpPrompt,
                value: nextUpPromptOptions.first { $0.0 == viewModel.nextUpPromptSeconds }?.1
                    ?? .settingsNextUpSecondsBeforeEnd(viewModel.nextUpPromptSeconds),
                options: nextUpPromptOptions.map { SettingsChoice(id: String($0.0), label: $0.1) }
            )

            // Three-way (labels fixed by the contract).
            choiceRow(
                .settingsControlIntros,
                .introSkipMode,
                value: .verbatim(viewModel.introSkipMode.label),
                options: IntroSkipMode.allCases.map { SettingsChoice(id: $0.wireValue, label: .verbatim($0.label)) }
            )

            choiceRow(
                .settingsControlCredits,
                .autoSkipCredits,
                value: viewModel.skipCredits ? .settingsOn : .settingsOff,
                options: onOffChoices
            )
        } header: {
            Text(.settingsSectionEpisodes)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .listRowBackground(Color.prairieGroupedCell)
    }

    // MARK: - Refused change

    private var rejectedChangeSection: some View {
        Section {
            Button(.settingsPlaybackRejectedOk) {
                Task { await viewModel.acknowledgeRejectedPlaybackChange() }
            }
        } header: {
            Text(.settingsHeldChangeHeader)
                .foregroundStyle(Color.prairieSecondaryText)
        } footer: {
            Text(SettingsViewModel.rejectedPlaybackChangeMessage)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .listRowBackground(Color.prairieGroupedCell)
    }

    // MARK: - Use Profile Settings

    private var resetSection: some View {
        Section {
            Button(.settingsProfileSettingsUseAll, systemImage: "arrow.counterclockwise", role: .destructive) {
                showUseProfileSettingsConfirmation = true
            }
        } footer: {
            Text(.settingsProfileSettingsResetFooter)
                .foregroundStyle(Color.prairieSecondaryText)
        }
        .listRowBackground(Color.prairieGroupedCell)
    }

    // MARK: - Options

    /// A profile-backed row. The row always shows the value that applies,
    /// wherever it comes from; the choice list leads with "Use Profile
    /// Setting", checked while this device has no value of its own.
    private func choiceRow(
        _ title: LocalizedStringResource,
        _ setting: ProfileBackedPlaybackSetting,
        value: LocalizedStringResource,
        options: [SettingsChoice]
    ) -> some View {
        SettingsChoiceRow(
            title: title,
            value: value,
            options: [useProfileSettingChoice] + options,
            selection: Binding(
                get: { viewModel.playbackSelectionTag(setting) },
                set: { viewModel.selectPlayback($0, for: setting) }
            )
        )
    }

    private var useProfileSettingChoice: SettingsChoice {
        SettingsChoice(id: SettingsViewModel.useProfileSettingTag, label: SettingsViewModel.useProfileSettingLabel)
    }

    private var resolutionChoices: [SettingsChoice] {
        PrairieQualityPresets.resolutionChoices.map {
            SettingsChoice(id: $0, label: .verbatim(PrairieQualityPresets.resolutionLabel($0)))
        }
    }

    private var maxBitrateChoices: [SettingsChoice] {
        [SettingsChoice(id: SettingsViewModel.noBitrateLimitTag, label: PrairieQualityPresets.noBitrateLimitLabel)]
            + viewModel.maxBitrateChoicesKbps.map {
                SettingsChoice(id: String($0), label: PrairieQualityPresets.bitrateLabel($0))
            }
    }

    #if os(iOS)
    private var cellularQualityChoices: [SettingsChoice] {
        // A pair no preset covers — set through the API, or written by a
        // client whose ladder has a rung this table does not — gets its own
        // entry describing what is actually stored, rather than the list
        // checking a preset the user never chose.
        var choices: [SettingsChoice] = []
        if !viewModel.usesProfileSetting(.cellularQuality), viewModel.cellularQualityPresetId == nil {
            choices.append(SettingsChoice(
                id: SettingsViewModel.customQualityTag,
                label: .verbatim(viewModel.cellularQualityLabel)
            ))
        }
        return choices + PrairieQualityPresets.all.map { SettingsChoice(id: $0.id, label: .verbatim($0.label)) }
    }
    #endif

    private var noAudioLanguageLabel: String {
        SettingPresentationMetadata.unsetLabel(
            for: .playbackAudioLanguage, fallback: "No preference", language: AppLanguage.language(of: locale)
        )
    }

    private var audioLanguageLabel: String {
        let code = viewModel.preferredAudioLanguage
        guard !code.isEmpty else { return noAudioLanguageLabel }
        return viewModel.audioLanguageOptions.first { $0.code == code }?.label ?? code
    }

    private var audioLanguageChoices: [SettingsChoice] {
        let stored = viewModel.hasStoredNoAudioLanguagePreference
            ? [SettingsChoice(id: "", label: .verbatim(noAudioLanguageLabel))]
            : []
        return stored + viewModel.audioLanguageOptions.map { SettingsChoice(id: $0.code, label: .verbatim($0.label)) }
    }

    private var onOffChoices: [SettingsChoice] {
        [
            SettingsChoice(id: SettingsViewModel.onTag, label: .settingsOn),
            SettingsChoice(id: SettingsViewModel.offTag, label: .settingsOff),
        ]
    }

    private var nextUpPromptOptions: [(Int, LocalizedStringResource)] {
        [
            (0, .settingsNextUpAtEnd),
            (10, .settingsNextUpSecondsBeforeEnd(10)),
            (30, .settingsNextUpSecondsBeforeEnd(30)),
            (60, .settingsNextUpMinutesBeforeEnd(1)),
            (120, .settingsNextUpMinutesBeforeEnd(2)),
        ]
    }
}

struct SettingsChoice: Identifiable, Hashable {
    let id: String
    let label: LocalizedStringResource

    // `LocalizedStringResource` isn't `Hashable`; equal choices share an id.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A settings row whose trailing text is the value that applies, which a
/// native Picker cannot show once its selected option is "Use Profile
/// Setting". Looks like the navigation-link pickers beside it on iOS and a
/// menu picker on macOS.
struct SettingsChoiceRow: View {
    let title: LocalizedStringResource
    let value: LocalizedStringResource
    let options: [SettingsChoice]
    @Binding var selection: String

    var body: some View {
        #if os(macOS)
        LabeledContent {
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(value)
            }
            .fixedSize()
        } label: {
            Text(title)
        }
        .foregroundStyle(Color.prairieOnSurface)
        #else
        NavigationLink {
            SettingsChoiceList(title: title, options: options, selection: $selection)
        } label: {
            LabeledContent {
                Text(value)
            } label: {
                Text(title)
            }
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(Color.prairieOnSurface)
        #endif
    }
}

#if !os(macOS)
/// The pushed choice list, in the style of the navigation-link picker it
/// stands in for: a checkmark on the selected row, and back on choosing.
struct SettingsChoiceList: View {
    let title: LocalizedStringResource
    let options: [SettingsChoice]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        selection = option.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(Color.prairieOnSurface)
                            Spacer(minLength: 16)
                            if option.id == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(option.id == selection ? .isSelected : [])
                }
            }
            .listRowBackground(Color.prairieGroupedCell)
        }
        .settingsListChrome()
        .navigationTitle(Text(title))
        .prairieNavigationTitleDisplayMode(.inline)
        .prairieToolbarColorSchemeDark()
    }
}
#endif
#endif
