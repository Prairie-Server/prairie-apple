#if !os(tvOS)
import SwiftUI

/// Card overlays settings. Layout principles, in order of importance:
///
/// 1. **Live preview, always visible**: the poster card is sticky at
///    the top of the screen so the user sees every change immediately
///    without scrolling back.
/// 2. **Glanceable category navigation**: a segmented picker filters
///    the long overlay list to one category at a time.
/// 3. **Per-overlay badge preview**: every row shows the actual
///    rendered badge it would produce, with the user's current preset
///    + accent applied, so the abstract "Resolution" label becomes a
///    concrete "4K" pill.
/// 4. **Inline disclosure**: tapping a row expands it to reveal the
///    visual corner picker + accent swatches + icon toggle. No sheets
///    for the common edit, no horizontally crammed controls.
struct CardOverlaySettingsView: View {
    @EnvironmentObject private var store: OverlayPrefsStore
    @State private var sampleVariant: OverlaySampleVariant = .movie
    @State private var category: OverlayCategory = .tech
    @State private var expandedOverlay: OverlayId?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                Color.clear.frame(height: previewHeight + 12)
                styleAndCategoryHeader
                contentList
                resetFooter
            }
            previewPane
        }
        .background(Color.continuumBackground.ignoresSafeArea())
        .navigationTitle("Card Overlays")
        .continuumNavigationTitleDisplayMode(.inline)
        .continuumToolbarColorSchemeDark()
        .task { await store.hydrateIfNeeded() }
    }

    private var previewHeight: CGFloat { 220 }

    // MARK: - Sticky preview

    private var previewPane: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                previewPoster
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Sample", selection: $sampleVariant) {
                        ForEach(OverlaySampleVariant.allCases) { variant in
                            Text(variant.label).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Style", selection: presetBinding) {
                        ForEach(PresetId.allCases, id: \.rawValue) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.continuumOnSurface)

                    Text(store.prefs.preset.description)
                        .font(.system(size: 11.5))
                        .foregroundColor(.continuumSecondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .frame(height: previewHeight)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.continuumBackground,
                    Color.continuumBackground.opacity(0.98),
                    Color.continuumBackground.opacity(0.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var previewPoster: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(white: 0.32),
                    Color(white: 0.18),
                    Color(white: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if store.enabled {
                CardOverlays(
                    data: sampleVariant.data,
                    prefs: store.prefs,
                    variant: .poster
                )
            }
        }
        .frame(width: 120, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }

    // MARK: - Category picker + admin notice

    @ViewBuilder
    private var styleAndCategoryHeader: some View {
        VStack(spacing: 14) {
            if !store.enabled {
                disabledBanner
            }
            Picker("Category", selection: $category) {
                ForEach(OverlayCategory.allCases, id: \.self) { cat in
                    Text(shortLabel(cat)).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var disabledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundColor(.continuumSecondaryText)
            Text("Overlays disabled by your server administrator.")
                .font(.system(size: 13))
                .foregroundColor(.continuumSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private func shortLabel(_ category: OverlayCategory) -> String {
        switch category {
        case .tech: return "Tech"
        case .ratings: return "Ratings"
        case .metadata: return "Info"
        case .ribbons: return "Ribbons"
        }
    }

    // MARK: - Overlay rows

    private var contentList: some View {
        LazyVStack(spacing: 8) {
            Text(category.description)
                .font(.system(size: 13))
                .foregroundColor(.continuumSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            ForEach(OverlayRegistry.defs(in: category), id: \.id) { def in
                OverlayRow(
                    def: def,
                    prefs: store.prefs,
                    sampleData: sampleVariant.data,
                    isExpanded: expandedOverlay == def.id,
                    onToggleExpand: { toggleExpand(def.id) },
                    onUpdate: { next in
                        Task { await store.setPrefs(next) }
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 12)
        .opacity(store.enabled ? 1 : 0.4)
        .disabled(!store.enabled)
    }

    private func toggleExpand(_ id: OverlayId) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if expandedOverlay == id {
                expandedOverlay = nil
            } else {
                expandedOverlay = id
            }
        }
    }

    // MARK: - Reset footer

    private var resetFooter: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                Task { await store.resetToDefaults() }
            } label: {
                Text("Reset to Defaults")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(!store.hasUserOverride)

            Text(store.hasUserOverride
                 ? "Clears your overrides and falls back to the server's baseline."
                 : "Using the server's baseline overlays.")
                .font(.system(size: 12))
                .foregroundColor(.continuumSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 40)
    }

    private var presetBinding: Binding<PresetId> {
        Binding(
            get: { store.prefs.preset },
            set: { newValue in
                var next = store.prefs
                next.preset = newValue
                Task { await store.setPrefs(next) }
            }
        )
    }
}

// MARK: - Overlay row

private struct OverlayRow: View {
    let def: OverlayDef
    let prefs: CardOverlayPrefs
    let sampleData: OverlayData
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onUpdate: (CardOverlayPrefs) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isExpanded ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: enabledBinding)
                .toggleStyle(SwitchToggleStyle(tint: .continuumOnSurface))
                .labelsHidden()
                .scaleEffect(0.85)
                .frame(width: 48)

            Button(action: onToggleExpand) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.label)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundColor(.continuumOnSurface)
                        Text(def.description)
                            .font(.system(size: 12))
                            .foregroundColor(.continuumSecondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    badgePreview
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.continuumSecondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(config.enabled ? 1.0 : 0.6)
    }

    private var badgePreview: some View {
        let preset = OverlayPresets.preset(prefs.preset)
        return OverlayBadgeView(
            state: OverlayBadgeRenderState.resolveForPreview(
                def: def,
                data: sampleData,
                prefs: previewPrefs,
                preset: preset
            ),
            preset: preset
        )
    }

    /// Standalone prefs document so the chip reflects THIS overlay's
    /// individual config (its accent / icon override), not the merged
    /// global state.
    private var previewPrefs: CardOverlayPrefs {
        var prefs = OverlaySchema.buildDefaults()
        prefs.preset = self.prefs.preset
        var item = config
        item.enabled = true
        prefs.items[def.id] = item
        return prefs
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().background(Color.white.opacity(0.08)).padding(.top, 10)

            HStack(alignment: .top, spacing: 16) {
                positionSection
                    .frame(width: 140)
                VStack(alignment: .leading, spacing: 14) {
                    if def.iconCapable {
                        iconToggle
                    }
                    accentPicker
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)

            if let note = def.availabilityNote {
                Text(note)
                    .font(.system(size: 11).italic())
                    .foregroundColor(.continuumSecondaryText)
            }
        }
        .disabled(!config.enabled)
        .opacity(config.enabled ? 1.0 : 0.5)
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Position")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.continuumSecondaryText)
            OverlayPositionGrid(
                selection: positionBinding,
                accent: config.accentColor.flatMap { Color(hex: $0) }
                    ?? def.defaultAccent.flatMap { Color(hex: $0) }
                    ?? .white,
                width: 70
            )
        }
    }

    private var iconToggle: some View {
        let preset = OverlayPresets.preset(prefs.preset)
        let resolved = config.showIcon ?? preset.preferIcon
        return Toggle(isOn: Binding(
            get: { resolved },
            set: { newValue in
                write { cfg in
                    cfg.showIcon = (newValue == preset.preferIcon) ? nil : newValue
                }
            }
        )) {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                Text("Show icon")
                    .font(.system(size: 13.5, weight: .medium))
            }
            .foregroundColor(.continuumOnSurface)
        }
        .toggleStyle(SwitchToggleStyle(tint: .continuumOnSurface))
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Accent")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.continuumSecondaryText)
                Spacer(minLength: 8)
                if config.accentColor != nil {
                    Button("Default") {
                        write { $0.accentColor = nil }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.continuumSecondaryText)
                }
            }
            // Two scrollable rows so the 12-color palette doesn't crash
            // into a single tiny line on a narrow iPhone screen.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(OverlayAccentPalette.entries, id: \.hex) { entry in
                        swatch(entry: entry)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func swatch(entry: (label: String, hex: String)) -> some View {
        let isSelected = config.accentColor?.lowercased() == entry.hex.lowercased()
        return Button {
            write { $0.accentColor = entry.hex }
        } label: {
            Circle()
                .fill(Color(hex: entry.hex))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().stroke(
                        isSelected ? .white : Color.white.opacity(0.20),
                        lineWidth: isSelected ? 3 : 1
                    )
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label)
    }

    // MARK: - Helpers

    private var config: OverlayItemConfig {
        prefs.items[def.id] ?? OverlayItemConfig(
            enabled: def.defaultEnabled,
            position: def.defaultPosition,
            accentColor: nil,
            showIcon: nil
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { config.enabled },
            set: { newValue in write { $0.enabled = newValue } }
        )
    }

    private var positionBinding: Binding<OverlayPosition> {
        Binding(
            get: { config.position },
            set: { newValue in write { $0.position = newValue } }
        )
    }

    private func write(_ mutate: (inout OverlayItemConfig) -> Void) {
        var items = prefs.items
        var entry = config
        mutate(&entry)
        items[def.id] = entry
        var next = prefs
        next.items = items
        onUpdate(next)
    }
}
#endif
