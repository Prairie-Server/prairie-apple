#if os(tvOS)
import SwiftUI

/// The Skyline cascading library selector (§5.3, mockups `a3`/`a6`).
///
/// Replaces the old full-screen library picker with an **anchored overlay
/// over the page** (never a pushed route, never a full-screen modal): a
/// glass panel below the tab, over a `scrim.dropdown`. One component, two
/// levels:
///
/// - **Level 1 — libraries.** A row per real library of the type (Rev 3
///   removed the merged `All <Type>` row). The current scope shows a `✓`;
///   the others a `›`. Single-library tabs collapse this away and show the
///   sections panel directly.
/// - **Level 2 — sections flyout.** Anchored to the focused library row's
///   right, listing that type's pill set (§3 / `TVLibraryPill.set`). It
///   follows focus up/down the library list after a 150 ms rest debounce
///   and never steals focus.
///
/// Focus contract (the hard part — see §5.3/§7):
/// - The host (`TVMainTabView`) keeps focus on the *tab* until d-pad
///   **down**, then flips `entersPanel` true and bumps `focusEntryToken`
///   to hand focus to the current-scope library row.
/// - **Up/down** rolls libraries; the flyout follows. **Right** enters the
///   flyout (first section); **left** returns to the library row.
/// - **Press** on a library row commits that scope → Browse landing.
///   **Press** on a flyout row commits the scope + that section.
/// - **Menu/Back** closes without changing anything (`onClose`).
///
/// The component itself owns no scope state; every outcome is a callback so
/// persistence and the page swap stay in the host.
struct TVCascadeSelector: View {
    let type: TVLibraryTabType
    /// Libraries of `type`, already ordered by sort order.
    let libraries: [Library]
    /// The library currently scoped for this tab (gets the `✓`, and the
    /// row focus lands here on entry).
    let currentScopeId: Int?
    /// Per-library item counts for the right-aligned count column, keyed by
    /// library id. Absent ids render no count (the model carries no count,
    /// so this is best-effort from loaded grids — §G).
    let counts: [Int: Int]
    /// Whether focus has entered the panel (host flips this on d-pad down).
    let entersPanel: Bool
    /// Bumped by the host the moment focus should enter the panel — lands
    /// on the current-scope library row.
    let focusEntryToken: Int
    /// Commit a library scope → its Browse landing.
    let onCommitLibrary: (Library) -> Void
    /// Commit a library scope + land on a specific section (pill).
    let onCommitSection: (Library, TVLibraryPill) -> Void
    /// Close without changing scope (Menu/Back, or focus left the bar).
    let onClose: () -> Void
    /// Reports whether any panel row currently holds focus, so the host can
    /// drop the tab's focused look once focus descends (§5.1) regardless of
    /// whether entry came via the explicit down hand-off or the engine.
    var onPanelFocusChanged: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Focus target inside the panel. `nil` while focus is still up on the
    /// tab (host hasn't entered yet).
    @FocusState private var focus: Focus?

    /// Library row the flyout is currently anchored to. Tracks `focus`
    /// after the rest debounce so rolling the list doesn't thrash it.
    @State private var flyoutAnchorId: Int?
    /// Debounce task for the flyout follow (§5.3).
    @State private var flyoutFollowTask: Task<Void, Never>?
    @State private var lastAppliedEntryToken = 0
    /// Each library row's top edge in the level-1 HStack's coordinate space.
    /// The flyout offsets to the anchored row's value to align tops (§5.3).
    @State private var rowTops: [Int: CGFloat] = [:]

    private enum Focus: Hashable {
        case library(Int)
        case section(Int, TVLibraryPill)
    }

    private var pills: [TVLibraryPill] { TVLibraryPill.set(for: type) }

    /// A single-library tab skips the library list and shows just that
    /// library's sections (§5.3 single-level panel).
    private var isSingleLibrary: Bool { libraries.count <= 1 }

    var body: some View {
        Group {
            if isSingleLibrary, let library = libraries.first {
                singleLevelPanel(for: library)
            } else {
                twoLevelPanel
            }
        }
        // Rows are inert until the host hands focus in on d-pad down. This
        // keeps focus on the tab while the panel is merely open (§5.3) and —
        // critically — stops the focus engine from grabbing a row on its own
        // when the user presses down, so the tab's `onMoveCommand(.down)`
        // fires and entry lands deterministically on the current-scope row.
        .disabled(!entersPanel)
        .onChange(of: focusEntryToken) { _, token in applyEntryToken(token) }
        .onChange(of: focus) { _, newValue in handleFocusChange(newValue) }
        .onChange(of: entersPanel) { _, entered in
            if !entered { focus = nil }
        }
        .onAppear {
            flyoutAnchorId = currentScopeId ?? libraries.first?.id
            if entersPanel { applyEntryToken(focusEntryToken) }
        }
        .onDisappear { flyoutFollowTask?.cancel() }
    }

    // MARK: - Two-level (multi-library)

    private var twoLevelPanel: some View {
        // The flyout's top aligns with the *focused library row* (§5.3
        // "top-aligned with the focused row"), not the panel header. Custom
        // VerticalAlignment guides don't survive the level-1 panel's
        // ScrollView / nested stacks, so the anchored row publishes its
        // frame in this HStack's coordinate space and the flyout offsets
        // down to match.
        HStack(alignment: .top, spacing: ContinuumTheme.Skyline.flyoutGap) {
            librariesPanel

            flyout
                .frame(width: ContinuumTheme.Skyline.flyoutWidth, alignment: .top)
                .opacity(flyoutAnchorId != nil ? 1 : 0)
                .offset(y: flyoutTopOffset)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: ContinuumTheme.Skyline.flyoutOpenDuration),
                    value: flyoutTopOffset
                )
        }
        .coordinateSpace(name: Self.cascadeSpace)
        .onPreferenceChange(TVCascadeRowAnchorKey.self) { tops in
            // Cache every row's top; the offset is derived so it updates
            // both when rows move (re-layout) and when the anchor changes.
            rowTops = tops
        }
        .fixedSize()
    }

    /// Vertical offset aligning the flyout's top with the anchored library
    /// row's top (§5.3). Derived so a change to either the row geometry or
    /// `flyoutAnchorId` re-aligns it.
    private var flyoutTopOffset: CGFloat {
        guard let anchorId = flyoutAnchorId else { return 0 }
        return rowTops[anchorId] ?? 0
    }

    private static let cascadeSpace = "cascade"

    private var librariesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(type.librariesHeader)

            libraryRows

            panelFooter
        }
        .padding(ContinuumTheme.Skyline.dropdownPadding)
        .frame(width: ContinuumTheme.Skyline.dropdownWidth, alignment: .leading)
        .modifier(TVCascadePanelChrome(
            cornerRadius: ContinuumTheme.Skyline.dropdownCornerRadius
        ))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(type.title) libraries")
    }

    @ViewBuilder
    private var libraryRows: some View {
        let rows = ForEach(libraries) { library in
            libraryRow(library)
        }

        if libraries.count > ContinuumTheme.Skyline.cascadeMaxVisibleRows {
            // Cap the visible height at the spec's 6 rows, then scroll
            // internally. The focus engine scrolls the focused row into
            // view as the list rolls.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) { rows }
            }
            .frame(maxHeight: estimatedRowHeight * CGFloat(ContinuumTheme.Skyline.cascadeMaxVisibleRows))
        } else {
            VStack(alignment: .leading, spacing: 0) { rows }
        }
    }

    private func libraryRow(_ library: Library) -> some View {
        let isFocused = focus == .library(library.id)
        let isCurrent = library.id == currentScopeId

        return Button {
            onCommitLibrary(library)
        } label: {
            TVCascadeLibraryRowLabel(
                title: library.name,
                systemImage: type.systemImage,
                count: counts[library.id],
                trailingGlyph: isCurrent ? "checkmark" : "chevron.right",
                isFocused: isFocused
            )
        }
        .buttonStyle(.continuumFlat)
        .focused($focus, equals: .library(library.id))
        // Report this row's top in the level-1 HStack's coordinate space so
        // the flyout can offset to align with the anchored row (§5.3). This
        // survives the panel's ScrollView / nested stacks, which a custom
        // VerticalAlignment guide would not.
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TVCascadeRowAnchorKey.self,
                    value: [library.id: geo.frame(in: .named(Self.cascadeSpace)).minY]
                )
            }
        )
        .accessibilityLabel(accessibilityLabel(for: library, isCurrent: isCurrent))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: - Single-level (single library)

    private func singleLevelPanel(for library: Library) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(library.name.uppercased())

            VStack(alignment: .leading, spacing: 0) {
                ForEach(pills, id: \.self) { pill in
                    sectionRow(pill, in: library)
                }
            }

            panelFooter
        }
        .padding(ContinuumTheme.Skyline.dropdownPadding)
        .frame(width: ContinuumTheme.Skyline.dropdownWidth, alignment: .leading)
        .modifier(TVCascadePanelChrome(
            cornerRadius: ContinuumTheme.Skyline.dropdownCornerRadius
        ))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(library.name) sections")
    }

    // MARK: - Flyout (level 2)

    @ViewBuilder
    private var flyout: some View {
        if let anchorId = flyoutAnchorId,
           let library = libraries.first(where: { $0.id == anchorId }) {
            VStack(alignment: .leading, spacing: 0) {
                flyoutHeader(library.name)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(pills, id: \.self) { pill in
                        sectionRow(pill, in: library)
                    }
                }
            }
            .padding(ContinuumTheme.Skyline.flyoutPadding)
            .frame(width: ContinuumTheme.Skyline.flyoutWidth, alignment: .leading)
            .modifier(TVCascadePanelChrome(
                cornerRadius: ContinuumTheme.Skyline.flyoutCornerRadius
            ))
            .fixedSize()
            // Crossfade the section list as the flyout follows focus to a
            // new library; the vertical move is handled by `flyoutTopOffset`
            // so a scale here would compound with it.
            .id(anchorId)
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(library.name) sections")
        }
    }

    private func sectionRow(_ pill: TVLibraryPill, in library: Library) -> some View {
        let isFocused = focus == .section(library.id, pill)

        return Button {
            onCommitSection(library, pill)
        } label: {
            TVCascadeSectionRowLabel(
                title: pill.title,
                systemImage: pill.systemImage,
                isFocused: isFocused
            )
        }
        .buttonStyle(.continuumFlat)
        .focused($focus, equals: .section(library.id, pill))
        .accessibilityLabel("\(pill.title), section")
    }

    // MARK: - Shared chrome

    private func panelHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: ContinuumTheme.Skyline.dropdownHeaderSize, design: .monospaced))
            .tracking(ContinuumTheme.Skyline.dropdownHeaderSize * 0.26)
            .foregroundStyle(Color.white.opacity(0.38))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .accessibilityHidden(true)
    }

    private func flyoutHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: ContinuumTheme.Skyline.flyoutHeaderSize, design: .monospaced))
            .tracking(ContinuumTheme.Skyline.flyoutHeaderSize * 0.26)
            .foregroundStyle(Color.white.opacity(0.38))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    private var panelFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.continuumDivider)
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            Text(footerCaption)
                .font(.system(size: ContinuumTheme.Skyline.dropdownHeaderSize, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.34))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
        }
        .accessibilityHidden(true)
    }

    private var footerCaption: String {
        isSingleLibrary
            ? "Press opens the section · Menu closes"
            : "Press opens the library · → jumps to a section · Menu closes"
    }

    // MARK: - Focus plumbing

    private func applyEntryToken(_ token: Int) {
        guard entersPanel, token > 0, token != lastAppliedEntryToken else { return }
        lastAppliedEntryToken = token
        if isSingleLibrary, let library = libraries.first {
            // Single-level: land on the first section (§5.3).
            focus = .section(library.id, pills.first ?? .browse)
        } else {
            // Two-level: land on the current-scope row, else the first.
            let target = currentScopeId ?? libraries.first?.id
            if let target {
                focus = .library(target)
                flyoutAnchorId = target
            }
        }
    }

    private func handleFocusChange(_ newValue: Focus?) {
        onPanelFocusChanged(newValue != nil)
        guard let newValue else { return }
        switch newValue {
        case .library(let id):
            scheduleFlyoutFollow(to: id)
        case .section(let id, _):
            // Focus is in the flyout — keep it anchored to that library and
            // cancel any pending follow so it doesn't snap away.
            flyoutFollowTask?.cancel()
            flyoutAnchorId = id
        }
    }

    /// Move the flyout to a newly focused library row after a rest
    /// debounce (§5.3) so rolling the list never thrashes the flyout.
    private func scheduleFlyoutFollow(to id: Int) {
        guard flyoutAnchorId != id else { return }
        flyoutFollowTask?.cancel()
        flyoutFollowTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: ContinuumTheme.Skyline.flyoutFollowDebounceMilliseconds * 1_000_000
            )
            guard !Task.isCancelled else { return }
            // Only follow if focus is still on this library row.
            guard focus == .library(id) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: ContinuumTheme.Skyline.flyoutOpenDuration)) {
                flyoutAnchorId = id
            }
        }
    }

    private var estimatedRowHeight: CGFloat {
        ContinuumTheme.Skyline.cascadeRowTextSize
            + ContinuumTheme.Skyline.cascadeRowPaddingVertical * 2
            + 6 // row spacing slack so the 6th row isn't clipped mid-glyph
    }

    private func accessibilityLabel(for library: Library, isCurrent: Bool) -> String {
        var label = library.name
        if let count = counts[library.id] {
            label += ", \(count) items"
        }
        if isCurrent { label += ", current library" }
        return label
    }
}

// MARK: - Row labels

/// Level-1 library row (§5.3): icon — name — count (right) — trailing
/// glyph. Inverts to white on focus, matching the bar/pill grammar.
private struct TVCascadeLibraryRowLabel: View {
    let title: String
    let systemImage: String
    let count: Int?
    let trailingGlyph: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: ContinuumTheme.Skyline.cascadeRowIconSize)

            Text(title)
                .font(.system(size: ContinuumTheme.Skyline.cascadeRowTextSize, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 12)

            if let count {
                Text(count.formatted(.number))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(foreground.opacity(isFocused ? 0.7 : 0.45))
                    .lineLimit(1)
            }

            Image(systemName: trailingGlyph)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground.opacity(isFocused ? 1 : 0.5))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, ContinuumTheme.Skyline.cascadeRowPaddingHorizontal)
        .padding(.vertical, ContinuumTheme.Skyline.cascadeRowPaddingVertical)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.Skyline.cascadeRowCornerRadius, style: .continuous)
                .fill(isFocused ? Color.white : Color.clear)
        )
        .focusEffectDisabled()
        .animation(ContinuumTheme.springAnimation, value: isFocused)
    }

    private var foreground: Color {
        isFocused ? .continuumBackground : .white.opacity(0.9)
    }
}

/// Flyout / single-level section row (§5.3): icon — name, inverting to
/// white on focus.
private struct TVCascadeSectionRowLabel: View {
    let title: String
    let systemImage: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 26)

            Text(title)
                .font(.system(size: ContinuumTheme.Skyline.flyoutRowTextSize, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(isFocused ? Color.continuumBackground : .white.opacity(0.86))
        .padding(.horizontal, ContinuumTheme.Skyline.flyoutRowPaddingHorizontal)
        .padding(.vertical, ContinuumTheme.Skyline.flyoutRowPaddingVertical)
        .background(
            RoundedRectangle(cornerRadius: ContinuumTheme.Skyline.flyoutRowCornerRadius, style: .continuous)
                .fill(isFocused ? Color.white : Color.clear)
        )
        .focusEffectDisabled()
        .animation(ContinuumTheme.springAnimation, value: isFocused)
    }
}

// MARK: - Panel chrome

/// Shared `glass.strong` panel backing for the level-1 panel and the
/// flyout — material blur under the tinted glass fill, hairline border,
/// drop shadow. Matches `TVProfileDropdown`'s panel treatment.
private struct TVCascadePanelChrome: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.continuumGlassStrong)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.continuumOutline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 34, y: 18)
    }
}

// MARK: - Flyout top alignment (§5.3)

/// Each library row's top edge, keyed by library id, in the level-1 panel
/// HStack's coordinate space. The flyout reads the anchored row's value to
/// offset its top into alignment — a preference instead of a custom
/// `VerticalAlignment`, which cannot cross the panel's ScrollView.
private struct TVCascadeRowAnchorKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
#endif
