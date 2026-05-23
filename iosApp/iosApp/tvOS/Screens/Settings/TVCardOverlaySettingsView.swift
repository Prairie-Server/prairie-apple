#if os(tvOS)
import SwiftUI

/// Two-pane card-overlay settings tuned for the 10-foot, focus-driven
/// remote experience. The left pane shows a large live preview poster
/// that updates as the user moves focus through the right pane. The
/// right pane is a single vertical list of overlay tiles — one focus
/// target per overlay, no horizontally-clustered controls.
///
/// Tapping a tile pushes a per-overlay detail sheet with big buttons
/// for enable / position / accent / icon. This avoids the Apple-TV-26
/// `NavigationLink`-in-`Form` ambiguity (see `TVSettingsView.swift`)
/// and gives each control room for its own focus ring.
struct TVCardOverlaySettingsView: View {
    @EnvironmentObject private var store: OverlayPrefsStore
    @State private var sampleVariant: OverlaySampleVariant = .movie
    @State private var detailOverlay: OverlayId?

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            previewPane
            controlsPane
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.continuumBackground.ignoresSafeArea())
        .task { await store.hydrateIfNeeded() }
        .sheet(item: Binding(
            get: { detailOverlay.map(IdentifiableOverlay.init) },
            set: { detailOverlay = $0?.id }
        )) { wrapper in
            TVOverlayDetailSheet(
                overlayId: wrapper.id,
                store: store,
                sampleData: sampleVariant.data
            )
        }
    }

    // MARK: - Left pane: live preview

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 28) {
            previewPoster
            sampleSwitcher
            presetChips
        }
        .frame(width: 520)
    }

    private var previewPoster: some View {
        // Show the live preview using either the focused overlay's
        // corner highlighted, or the full configuration when nothing
        // is focused. Helps the user see *which* overlay they're
        // currently editing without scanning the list.
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(white: 0.30),
                    Color(white: 0.16),
                    Color(white: 0.06),
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
        .frame(width: 420, height: 630)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    private var sampleSwitcher: some View {
        HStack(spacing: 12) {
            ForEach(OverlaySampleVariant.allCases) { variant in
                Button {
                    sampleVariant = variant
                } label: {
                    Text(variant.label)
                        .font(.system(size: 22, weight: .medium))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(sampleVariant == variant ? .white : .gray)
            }
            Spacer(minLength: 0)
        }
    }

    private var presetChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text(store.prefs.preset.description)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 10) {
                ForEach(PresetId.allCases, id: \.rawValue) { preset in
                    presetChip(preset)
                }
            }
        }
    }

    private func presetChip(_ preset: PresetId) -> some View {
        let selected = store.prefs.preset == preset
        return Button {
            var next = store.prefs
            next.preset = preset
            Task { await store.setPrefs(next) }
        } label: {
            Text(preset.label)
                .font(.system(size: 18, weight: selected ? .bold : .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .white : .gray)
    }

    // MARK: - Right pane: overlay rows

    private var controlsPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !store.enabled {
                disabledNotice
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(OverlayCategory.allCases, id: \.self) { category in
                        categoryHeader(category)
                        ForEach(OverlayRegistry.defs(in: category), id: \.id) { def in
                            overlayTile(def)
                        }
                    }
                    resetButton
                }
                .padding(.bottom, 40)
            }
            .disabled(!store.enabled)
            .opacity(store.enabled ? 1 : 0.35)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disabledNotice: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
            Text("Card overlays have been disabled by your server administrator.")
                .font(.system(size: 20, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
    }

    private func categoryHeader(_ category: OverlayCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.displayName)
                .font(.system(size: 26, weight: .semibold))
            Text(category.description)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func overlayTile(_ def: OverlayDef) -> some View {
        TVOverlayTile(
            def: def,
            config: store.prefs.items[def.id] ?? defaultConfig(for: def),
            preset: OverlayPresets.preset(store.prefs.preset),
            sampleData: sampleVariant.data
        ) {
            detailOverlay = def.id
        }
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            Task { await store.resetToDefaults() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset to Defaults")
            }
            .font(.system(size: 20, weight: .medium))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(!store.hasUserOverride)
        .padding(.top, 24)
    }

    private func defaultConfig(for def: OverlayDef) -> OverlayItemConfig {
        OverlayItemConfig(
            enabled: def.defaultEnabled,
            position: def.defaultPosition,
            accentColor: nil,
            showIcon: nil
        )
    }
}

/// Single overlay row on the right pane. Whole row is one focus target.
/// Layout: status pill | name & description | rendered badge preview |
/// position indicator | chevron.
private struct TVOverlayTile: View {
    let def: OverlayDef
    let config: OverlayItemConfig
    let preset: OverlayPreset
    let sampleData: OverlayData
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 24) {
                statusPill
                VStack(alignment: .leading, spacing: 4) {
                    Text(def.label)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(def.description)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 16)
                badgePreview
                positionChip
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused ? Color.white.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .opacity(config.enabled ? 1.0 : 0.55)
    }

    private var statusPill: some View {
        ZStack {
            Circle()
                .fill(config.enabled ? Color.green : Color.white.opacity(0.18))
                .frame(width: 14, height: 14)
        }
        .frame(width: 24, height: 24)
    }

    private var badgePreview: some View {
        // Render the live badge so the user sees *what they'd get* —
        // accent, icon, preset shape all reflected.
        OverlayBadgeView(
            state: OverlayBadgeRenderState.resolveForPreview(
                def: def,
                data: sampleData,
                prefs: previewPrefs,
                preset: preset
            ),
            preset: preset
        )
        .frame(minWidth: 70, alignment: .center)
    }

    /// Standalone prefs document so the preview reflects this overlay's
    /// individual config (enabled/accent/icon) instead of the global state.
    /// `enabled` is forced true so the chip always renders.
    private var previewPrefs: CardOverlayPrefs {
        var prefs = OverlaySchema.buildDefaults()
        prefs.preset = preset.id
        var item = config
        item.enabled = true
        prefs.items[def.id] = item
        return prefs
    }

    private var positionChip: some View {
        Text(config.position.displayName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
    }
}

// MARK: - Detail sheet

/// Per-overlay detail sheet. Big preview + four corner-illustrated
/// position buttons + accent grid + icon toggle. Each control gets
/// its own focus row so the remote always has an obvious target.
private struct TVOverlayDetailSheet: View {
    let overlayId: OverlayId
    @ObservedObject var store: OverlayPrefsStore
    let sampleData: OverlayData
    @Environment(\.dismiss) private var dismiss

    private var def: OverlayDef? { OverlayRegistry.def(for: overlayId) }
    private var config: OverlayItemConfig {
        store.prefs.items[overlayId] ?? OverlayItemConfig(
            enabled: def?.defaultEnabled ?? true,
            position: def?.defaultPosition ?? .topLeft,
            accentColor: nil,
            showIcon: nil
        )
    }
    private var preset: OverlayPreset { OverlayPresets.preset(store.prefs.preset) }

    var body: some View {
        if let def {
            ScrollView {
                VStack(spacing: 36) {
                    header(def)
                    preview(def)
                    enableSection
                    positionSection
                    accentSection(def)
                    if def.iconCapable {
                        iconSection
                    }
                    if let note = def.availabilityNote {
                        Text(note)
                            .font(.system(size: 16).italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 80)
                    }
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity)
            }
            .background(Color.continuumBackground.ignoresSafeArea())
        } else {
            Text("Overlay not found")
        }
    }

    private func header(_ def: OverlayDef) -> some View {
        VStack(spacing: 8) {
            Text(def.label)
                .font(.system(size: 38, weight: .bold))
            Text(def.description)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func preview(_ def: OverlayDef) -> some View {
        // Show a focused poster preview with ONLY this overlay enabled
        // so the user sees the effect of their per-overlay tweaks
        // (accent, icon, position) without other badges competing.
        var prefs = OverlaySchema.buildDefaults()
        prefs.preset = preset.id
        for id in OverlayId.allCases {
            prefs.items[id]?.enabled = false
        }
        var entry = config
        entry.enabled = true
        prefs.items[def.id] = entry

        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(white: 0.30),
                    Color(white: 0.16),
                    Color(white: 0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            CardOverlays(data: sampleData, prefs: prefs, variant: .poster)
        }
        .frame(width: 320, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    // MARK: enable

    private var enableSection: some View {
        sectionWrap(title: "Visibility") {
            HStack(spacing: 20) {
                visibilityButton(label: "On",  active: config.enabled)  { setEnabled(true) }
                visibilityButton(label: "Off", active: !config.enabled) { setEnabled(false) }
            }
        }
    }

    private func visibilityButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                Text(label)
                    .font(.system(size: 22, weight: .medium))
            }
            .frame(minWidth: 160)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(active ? .white : .gray)
    }

    // MARK: position

    private var positionSection: some View {
        sectionWrap(title: "Position") {
            HStack(alignment: .top, spacing: 50) {
                OverlayPositionGrid(
                    selection: Binding(
                        get: { config.position },
                        set: { newValue in
                            patch { $0.position = newValue }
                        }
                    ),
                    accent: config.accentColor.flatMap { Color(hex: $0) } ?? .white,
                    width: 220
                )
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(OverlayPosition.allCases, id: \.rawValue) { pos in
                        positionRow(pos)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func positionRow(_ pos: OverlayPosition) -> some View {
        Button {
            patch { $0.position = pos }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: config.position == pos ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                Text(pos.displayName)
                    .font(.system(size: 20, weight: .medium))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(config.position == pos ? .white : .gray)
    }

    // MARK: accent

    private func accentSection(_ def: OverlayDef) -> some View {
        sectionWrap(title: "Accent Color") {
            VStack(spacing: 20) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 20)],
                    spacing: 20
                ) {
                    ForEach(OverlayAccentPalette.entries, id: \.hex) { entry in
                        accentSwatch(hex: entry.hex, label: entry.label)
                    }
                }
                Button {
                    patch { $0.accentColor = nil }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.backward")
                        Text(def.defaultAccent == nil ? "No Accent" : "Default")
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(config.accentColor == nil ? .white : .gray)
            }
        }
    }

    private func accentSwatch(hex: String, label: String) -> some View {
        let selected = config.accentColor?.lowercased() == hex.lowercased()
        return Button {
            patch { $0.accentColor = hex }
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(selected ? .white : Color.white.opacity(0.18), lineWidth: selected ? 4 : 1)
                    )
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: icon

    private var iconSection: some View {
        let preferIcon = preset.preferIcon
        let resolvedShow = config.showIcon ?? preferIcon
        return sectionWrap(title: "Icon") {
            HStack(spacing: 20) {
                visibilityButton(label: "Show Icon", active: resolvedShow) {
                    setShowIcon(true, presetDefault: preferIcon)
                }
                visibilityButton(label: "Hide Icon", active: !resolvedShow) {
                    setShowIcon(false, presetDefault: preferIcon)
                }
            }
        }
    }

    // MARK: helpers

    private func sectionWrap<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40)
    }

    private func setEnabled(_ enabled: Bool) {
        patch { $0.enabled = enabled }
    }

    private func setShowIcon(_ show: Bool, presetDefault: Bool) {
        patch { cfg in
            cfg.showIcon = (show == presetDefault) ? nil : show
        }
    }

    private func patch(_ mutate: (inout OverlayItemConfig) -> Void) {
        guard let def else { return }
        var items = store.prefs.items
        var entry = items[overlayId] ?? OverlayItemConfig(
            enabled: def.defaultEnabled,
            position: def.defaultPosition,
            accentColor: nil,
            showIcon: nil
        )
        mutate(&entry)
        items[overlayId] = entry
        var next = store.prefs
        next.items = items
        Task { await store.setPrefs(next) }
    }
}

/// Identifiable wrapper so `OverlayId` can drive `.sheet(item:)`.
private struct IdentifiableOverlay: Identifiable, Hashable {
    let id: OverlayId
}
#endif
