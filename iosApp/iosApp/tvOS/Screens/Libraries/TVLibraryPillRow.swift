#if os(tvOS)
import SwiftUI

/// Sub-destinations of a Skyline library-type tab (§3, §5.2). Peer
/// destinations under the top bar — never hidden modes.
enum TVLibraryPill: String, Hashable, CaseIterable {
    case browse
    case collections
    case genres
    case aToZ
    case recentlyAdded

    var title: String {
        switch self {
        case .browse: return "Browse"
        case .collections: return "Collections"
        case .genres: return "Genres"
        case .aToZ: return "A–Z"
        case .recentlyAdded: return "Recently Added"
        }
    }

    /// SF Symbol shown beside the section name in the cascade flyout
    /// (§5.3). The pill row itself stays text-only per the mockups.
    var systemImage: String {
        switch self {
        case .browse: return "rectangle.stack"
        case .collections: return "square.stack.3d.up"
        case .genres: return "theatermasks"
        case .aToZ: return "textformat.abc"
        case .recentlyAdded: return "clock.arrow.circlepath"
        }
    }

    /// Per-type pill sets. `Browse` is always first and the landing
    /// default; sets stay ≤5 by design so the row never scrolls.
    static func set(for type: TVLibraryTabType) -> [TVLibraryPill] {
        switch type {
        case .movies, .series:
            return [.browse, .collections, .genres, .aToZ, .recentlyAdded]
        case .music:
            // Guide §3 wants Browse · Artists · Albums · Playlists ·
            // Genres, but artist/album/playlist browse surfaces don't
            // exist on this client yet.
            return [.browse, .collections]
        case .audiobooks:
            // Guide §3 wants Browse · Authors · Series · Collections ·
            // A–Z, but author/book-series browse surfaces don't exist on
            // this client yet.
            return [.browse, .collections, .aToZ]
        }
    }
}

/// The sub-destination pill row that replaced the Recommended/Collections
/// mode slider (§5.2). Lives 30pt under the top bar, floats over the
/// page's hero, and commits on **press** — moving focus across pills never
/// changes content.
struct TVLibraryPillRow: View {
    let pills: [TVLibraryPill]
    let selected: TVLibraryPill
    /// Right-aligned tertiary scope caption (the active library's name
    /// for now; item count + freshness arrive with the Phase 3 scopes).
    let caption: String?
    /// Imperative focus kick: when this changes, focus jumps to the
    /// selected pill (tab entry on grid pills, hand-up fallback).
    var focusRequest: Int = 0
    let onSelect: (TVLibraryPill) -> Void
    /// Up at the row's boundary hands focus to the top bar.
    let onMoveUp: (() -> Void)?

    @FocusState private var focusedPill: TVLibraryPill?
    @State private var lastAppliedFocusRequest = 0

    private var rowHasFocus: Bool { focusedPill != nil }

    var body: some View {
        HStack(spacing: ContinuumTheme.Skyline.pillSpacing) {
            ForEach(Array(pills.enumerated()), id: \.element) { index, pill in
                pillButton(pill, index: index)
            }

            Spacer(minLength: ContinuumTheme.Skyline.pillSpacing)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: ContinuumTheme.Skyline.pillCaptionSize, weight: .medium))
                    .foregroundStyle(Color.continuumOnSurface.opacity(0.38))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, ContinuumTheme.Skyline.safeAreaX)
        .padding(.top, ContinuumTheme.Skyline.pillRowTopInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .focusSection()
        .onMoveCommand { direction in
            // Fires only when the focus engine can't move within the row —
            // i.e. at the zone boundary. Up crosses into the (suppressed)
            // top bar via the shell's imperative hand-up.
            if direction == .up {
                onMoveUp?()
            }
        }
        .onAppear { applyFocusRequest(focusRequest) }
        .onChange(of: focusRequest) { _, request in applyFocusRequest(request) }
    }

    private func pillButton(_ pill: TVLibraryPill, index: Int) -> some View {
        let isSelected = pill == selected
        let isFocused = focusedPill == pill
        // The selected pill keeps the inverted "you are here" look while
        // focus is elsewhere on the page; while the row itself has focus,
        // inversion marks the focused pill and the selected one drops to
        // the `chrome.selected` capsule so the two never read identically.
        let isInverted = isFocused || (isSelected && !rowHasFocus)

        return Button {
            onSelect(pill)
        } label: {
            Text(pill.title)
                .font(.system(size: ContinuumTheme.Skyline.pillLabelSize, weight: .semibold))
                .foregroundStyle(pillForeground(isInverted: isInverted, isSelected: isSelected))
                .lineLimit(1)
                .padding(.horizontal, ContinuumTheme.Skyline.pillPaddingHorizontal)
                .padding(.vertical, ContinuumTheme.Skyline.pillPaddingVertical)
                .background(
                    Capsule().fill(pillFill(isInverted: isInverted, isSelected: isSelected))
                )
                .overlay {
                    Capsule().strokeBorder(
                        pillBorder(isInverted: isInverted, isSelected: isSelected),
                        lineWidth: 1
                    )
                }
                .focusEffectDisabled()
                .animation(ContinuumTheme.springAnimation, value: isInverted)
        }
        .buttonStyle(.continuumFlat)
        .focused($focusedPill, equals: pill)
        .accessibilityLabel("\(pill.title), \(index + 1) of \(pills.count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pillFill(isInverted: Bool, isSelected: Bool) -> Color {
        if isInverted { return .white }
        if isSelected { return .continuumChromeSelectedFill }
        return .continuumChromeRestingFill
    }

    private func pillBorder(isInverted: Bool, isSelected: Bool) -> Color {
        if isInverted { return .clear }
        if isSelected { return .continuumChromeSelectedBorder }
        return .continuumChromeRestingBorder
    }

    private func pillForeground(isInverted: Bool, isSelected: Bool) -> Color {
        if isInverted { return .continuumBackground }
        if isSelected { return .white }
        return .white.opacity(0.62)
    }

    private func applyFocusRequest(_ request: Int) {
        guard request > 0, request != lastAppliedFocusRequest else { return }
        lastAppliedFocusRequest = request
        focusedPill = selected
    }
}
#endif
