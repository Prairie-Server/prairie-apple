import SwiftUI

/// Cross-platform stand-in for `Stepper`. On iOS we use Stepper; on tvOS we
/// fall back to a Picker that enumerates the full integer range by `step`
/// (tvOS omits Stepper, and a focus-driven list spinner matches Apple's
/// remote idiom better than a continuous stepper anyway).
private struct RangeSpinner<Value: Hashable & Strideable>: View
where Value.Stride: SignedInteger {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let display: (Value) -> String
    let onCommit: () -> Void

    var body: some View {
        #if os(tvOS)
        Picker(title, selection: Binding(
            get: { value },
            set: { newValue in
                value = newValue
                onCommit()
            }
        )) {
            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { option in
                Text(display(option)).tag(option)
            }
        }
        #else
        Stepper(
            value: Binding(
                get: { value },
                set: { newValue in
                    value = newValue
                    onCommit()
                }
            ),
            in: range,
            step: step
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(display(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        #endif
    }
}

/// Same as `RangeSpinner` but for `Double` values — Stepper's Strideable
/// bound insists on SignedInteger so we special-case doubles.
private struct DoubleRangeSpinner: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String
    let onCommit: () -> Void

    var body: some View {
        #if os(tvOS)
        let options = Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
        Picker(title, selection: Binding(
            get: { nearest(to: value, in: options) },
            set: { newValue in
                value = newValue
                onCommit()
            }
        )) {
            ForEach(options, id: \.self) { option in
                Text(display(option)).tag(option)
            }
        }
        #else
        Stepper(
            value: Binding(
                get: { value },
                set: { newValue in
                    value = newValue
                    onCommit()
                }
            ),
            in: range,
            step: step
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(display(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        #endif
    }

    private func nearest(to target: Double, in options: [Double]) -> Double {
        options.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
    }
}

/// Top-level settings sheet: speed, aspect, HDR, audio/sub sync, sleep timer,
/// passthrough, subtitle styling, auto-play next. Apply-on-change — the VM's
/// `applySettingsToPlayer()` is already called on file-loaded; live mutation
/// re-applies one property at a time through the binding helpers below.
struct PlayerSettingsSheet: View {
    let viewModel: PlayerViewModel
    let sleepTimer: SleepTimer

    var body: some View {
        navigation {
            Form {
                routeSection
                qualitySection
                playbackSection
                hdrSection
                syncSection
                sleepSection
                subtitleStylingSection
            }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #else
            .background(Color.black.opacity(0.85).ignoresSafeArea())
            #endif
            #if os(iOS)
            .navigationTitle("Playback Settings")
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Sections

    private var routeSection: some View {
        Section("Route") {
            ForEach(viewModel.routeStatusRows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                    Spacer()
                    Text(row.value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let summary = viewModel.routeDecisionSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            ForEach(Array(viewModel.routeWarnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private var qualitySection: some View {
        Section("Quality") {
            Picker("Quality", selection: Binding(
                get: { viewModel.activeQualityId },
                set: { newValue in
                    viewModel.switchQuality(newValue)
                }
            )) {
                ForEach(viewModel.qualityOptions) { option in
                    if let subtitle = option.subtitle {
                        VStack(alignment: .leading) {
                            Text(option.label)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option.id)
                    } else {
                        Text(option.label).tag(option.id)
                    }
                }
            }

            if viewModel.isQualitySwitching {
                HStack {
                    ProgressView()
                    Text("Switching quality...")
                        .foregroundStyle(.secondary)
                }
            } else if let error = viewModel.qualitySwitchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var playbackSection: some View {
        Section("Playback") {
            // Speed — 0.5x through 3.0x, step 0.25x. Constrained to a Picker
            // so the tvOS remote gets a spinner instead of a free slider
            // (which doesn't focus well).
            Picker("Speed", selection: Binding(
                get: { viewModel.settings.playbackSpeed },
                set: { newValue in
                    viewModel.setPlaybackSpeed(newValue)
                }
            )) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], id: \.self) { speed in
                    Text(speed == 1.0 ? "Normal (1.0×)" : String(format: "%.2f×", speed))
                        .tag(speed)
                }
            }

            if viewModel.backendCapabilities.supportsVideoGravity {
                Picker("Aspect", selection: Binding(
                    get: { viewModel.settings.videoGravity },
                    set: { newValue in
                        viewModel.setVideoGravity(newValue)
                    }
                )) {
                    ForEach(VideoGravity.allCases, id: \.self) { gravity in
                        Text(gravity.label).tag(gravity)
                    }
                }
            }

            Toggle("Auto-play next episode", isOn: Binding(
                get: { viewModel.settings.autoPlayNextEpisode },
                set: { viewModel.settings.setAutoPlayNextEpisode($0) }
            ))
        }
    }

    private var hdrSection: some View {
        Group {
            if viewModel.backendCapabilities.supportsHDRToggle {
                Section {
                    Toggle("HDR passthrough", isOn: Binding(
                        get: { viewModel.settings.hdrEnabled },
                        set: { newValue in
                            viewModel.setHDREnabled(newValue)
                        }
                    ))
                    Text("Disable if colors look washed out or your display tone-maps incorrectly.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                } header: {
                    Text("Display")
                }
            }
        }
    }

    private var syncSection: some View {
        Group {
            if viewModel.backendCapabilities.supportsAudioDelay
                || viewModel.backendCapabilities.supportsSubtitleDelay {
                Section("Sync") {
                    if viewModel.backendCapabilities.supportsAudioDelay {
                        RangeSpinner(
                            title: "Audio delay",
                            value: Binding(
                                get: { viewModel.settings.audioSyncMs },
                                set: { viewModel.settings.audioSyncMs = $0 }
                            ),
                            range: -5000...5000,
                            step: 50,
                            display: { formatMs($0) },
                            onCommit: {
                                viewModel.setAudioSyncMilliseconds(viewModel.settings.audioSyncMs)
                            }
                        )
                    }

                    if viewModel.backendCapabilities.supportsSubtitleDelay {
                        RangeSpinner(
                            title: "Subtitle delay",
                            value: Binding(
                                get: { viewModel.settings.subtitleSyncMs },
                                set: { viewModel.settings.subtitleSyncMs = $0 }
                            ),
                            range: -10000...10000,
                            step: 100,
                            display: { formatMs($0) },
                            onCommit: {
                                viewModel.setSubtitleSyncMilliseconds(viewModel.settings.subtitleSyncMs)
                            }
                        )
                    }
                }
            }
        }
    }

    private var sleepSection: some View {
        Section("Sleep timer") {
            Picker("Stop after", selection: Binding<Int>(
                get: { sleepTimer.isActive ? sleepTimerMinutesOption(remaining: sleepTimer.remainingSeconds) : 0 },
                set: { newValue in
                    if newValue == 0 {
                        sleepTimer.cancel()
                    } else {
                        sleepTimer.start(minutes: newValue)
                    }
                }
            )) {
                Text("Off").tag(0)
                Text("5 min").tag(5)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("45 min").tag(45)
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
            }

            if sleepTimer.isActive {
                HStack {
                    Text("Remaining")
                    Spacer()
                    Text(PlayerTimeFormatter.formatHMS(Double(sleepTimer.remainingSeconds)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var subtitleStylingSection: some View {
        Group {
            if viewModel.backendCapabilities.supportsSubtitleStyling {
                Section("Subtitle appearance") {
                    Toggle("Save for this device and profile", isOn: Binding(
                        get: { viewModel.settings.subtitleUsesDeviceAppearanceOverride },
                        set: { enabled in
                            Task { await viewModel.setSubtitleDeviceOverrideEnabled(enabled) }
                        }
                    ))

                    Picker("Font size", selection: appearanceEnumBinding(\.fontSize, SubtitleFontSizePreset.self)) {
                        ForEach(SubtitleFontSizePreset.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }

                    Picker("Font family", selection: appearanceEnumBinding(\.fontFamily, SubtitleFontFamilyPreset.self)) {
                        ForEach(SubtitleFontFamilyPreset.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }

                    Picker("Font color", selection: appearanceStringBinding(\.fontColor)) {
                        ForEach(SubtitleAppearance.fontColors, id: \.hex) { color in
                            Text(color.label).tag(color.hex)
                        }
                    }

                    Toggle("Text outline", isOn: appearanceBoolBinding(\.textOutline))

                    Picker("Outline color", selection: appearanceStringBinding(\.textOutlineColor)) {
                        ForEach(SubtitleAppearance.outlineColors, id: \.hex) { color in
                            Text(color.label).tag(color.hex)
                        }
                    }
                    .disabled(!viewModel.settings.subtitleAppearance.textOutline && viewModel.settings.subtitleAppearance.backgroundStyle != .outline)

                    Picker("Background style", selection: appearanceEnumBinding(\.backgroundStyle, SubtitleBackgroundStylePreset.self)) {
                        ForEach(SubtitleBackgroundStylePreset.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }

                    Picker("Background opacity", selection: appearanceIntBinding(\.backgroundOpacity)) {
                        ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { value in
                            Text("\(value)%").tag(String(value))
                        }
                    }
                    .disabled(viewModel.settings.subtitleAppearance.backgroundStyle != .box)

                    Picker("Background color", selection: appearanceStringBinding(\.backgroundColor)) {
                        ForEach(SubtitleAppearance.backgroundColors, id: \.hex) { color in
                            Text(color.label).tag(color.hex)
                        }
                    }
                    .disabled(viewModel.settings.subtitleAppearance.backgroundStyle != .box)

                    Picker("Position", selection: appearanceEnumBinding(\.position, SubtitlePositionPreset.self)) {
                        ForEach(SubtitlePositionPreset.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                }
            }
        }
    }

    private func appearanceStringBinding(_ keyPath: WritableKeyPath<SubtitleAppearance, String>) -> Binding<String> {
        Binding(
            get: { viewModel.settings.subtitleAppearance[keyPath: keyPath] },
            set: { value in
                var next = viewModel.settings.subtitleAppearance
                next[keyPath: keyPath] = value
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    private func appearanceIntBinding(_ keyPath: WritableKeyPath<SubtitleAppearance, Int>) -> Binding<String> {
        Binding(
            get: { String(viewModel.settings.subtitleAppearance[keyPath: keyPath]) },
            set: { value in
                guard let intValue = Int(value) else { return }
                var next = viewModel.settings.subtitleAppearance
                next[keyPath: keyPath] = intValue
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    private func appearanceBoolBinding(_ keyPath: WritableKeyPath<SubtitleAppearance, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.subtitleAppearance[keyPath: keyPath] },
            set: { value in
                var next = viewModel.settings.subtitleAppearance
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
            get: { viewModel.settings.subtitleAppearance[keyPath: keyPath].rawValue },
            set: { rawValue in
                guard let value = Value(rawValue: rawValue) else { return }
                var next = viewModel.settings.subtitleAppearance
                next[keyPath: keyPath] = value
                Task { await viewModel.setSubtitleAppearance(next) }
            }
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func navigation<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(iOS)
        NavigationStack { content() }
        #else
        content()
        #endif
    }

    private func formatMs(_ ms: Int) -> String {
        if ms == 0 { return "0 ms" }
        let sign = ms > 0 ? "+" : ""
        return "\(sign)\(ms) ms"
    }


    /// Map the timer's remaining seconds back to the nearest whole-minute
    /// option tag for the picker. Picker values are the initial minute count,
    /// so this snaps the selection back to whichever preset the user picked.
    private func sleepTimerMinutesOption(remaining seconds: Int) -> Int {
        let minutes = (seconds + 59) / 60
        for candidate in [5, 15, 30, 45, 60, 120] {
            if minutes <= candidate { return candidate }
        }
        return 120
    }
}
