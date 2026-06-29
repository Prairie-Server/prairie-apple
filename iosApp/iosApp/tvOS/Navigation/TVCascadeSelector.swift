#if os(tvOS)
import SwiftUI
import os // TVFOCUS-DEBUG: temporary focus tracing

// TVFOCUS-DEBUG: temporary focus tracing (strip before finalizing)
private let tvFocusCascadeLog = Logger(subsystem: "com.silo.tvfocus", category: "cascade")

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
/// - The host (`TVMainTabView`) keeps focus on the *tab* while dwell only
///   previews the panel. D-pad **down** flips `entersPanel` true and bumps
///   `focusEntryToken`, landing on the current-scope library row.
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
    /// Whether focus has entered the panel.
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
    /// drop the tab's focused look once focus descends (§5.1).
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

    /// Focus target inside the panel: a level-1 library row, or a level-2
    /// section row (scoped to its library so the same pill in two libraries
    /// stays distinct). Cross-column moves set this directly (`moveFromLibrary`
    /// / `moveFromSection`).
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
        // Dwell-open menus are passive previews: until the host hands focus
        // in on d-pad down, rows render as labels instead of disabled Buttons.
        // Disabled focusable controls still perturb tvOS's focus graph and
        // make the bar briefly drop focus when the submenu appears.
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
        // frame in this HStack's coordinate space and the flyout pads its
        // top down to match.
        //
        // This MUST be layout padding, not `.offset(y:)`. `.offset` is a
        // render-only transform: it moves the flyout visually but leaves its
        // *focus* frame at the top of the HStack. tvOS resolves directional
        // moves from the layout frame, so a d-pad Right from a library row
        // lower in the list finds no geometrically valid target to its right
        // and focus never enters the flyout (and `defaultFocus` can't help —
        // it only refines *which* row to land on once the engine has decided
        // to enter the section, it can't initiate the move). Padding moves the
        // real layout frame, so the focus engine sees the flyout where it
        // actually appears and the Right move resolves geometrically.
        HStack(alignment: .top, spacing: ContinuumTheme.Skyline.flyoutGap) {
            librariesPanel

            flyout
                .frame(width: ContinuumTheme.Skyline.flyoutWidth, alignment: .top)
                .opacity(flyoutAnchorId != nil ? 1 : 0)
                .padding(.top, flyoutTopOffset)
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
        .modifier(TVSkylinePanelChrome(
            cornerRadius: ContinuumTheme.Skyline.dropdownCornerRadius
        ))
        // One focus section so vertical d-pad rolls the library list and a
        // Left/Right move treats the column as a unit. Cross-column moves are
        // handled explicitly per row (`moveFromLibrary`) via onMoveCommand +
        // @FocusState — NOT by `defaultFocus`. A `defaultFocus(.userInitiated)`
        // here actively traps focus: `.userInitiated` resets focus back to the
        // default on every *user-initiated* move, so it ate the Right press
        // that should have crossed into the flyout.
        .focusSection()
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

    @ViewBuilder
    private func libraryRow(_ library: Library) -> some View {
        let isFocused = focus == .library(library.id)
        let isCurrent = library.id == currentScopeId
        let label = TVCascadeLibraryRowLabel(
            title: library.name,
            systemImage: type.systemImage,
            trailingGlyph: isCurrent ? "checkmark" : "chevron.right",
            isFocused: isFocused
        )

        if entersPanel {
            Button {
                onCommitLibrary(library)
            } label: {
                label
            }
            .buttonStyle(.continuumFlat)
            .focused($focus, equals: .library(library.id))
            // Cross-column move is driven explicitly, not by geometry: a d-pad
            // Right claims the flyout's first section through @FocusState, which
            // wins over the focus engine. Geometry alone is unreliable here
            // because the flyout chases the focused row (its first actionable
            // row sits a header-height below, often outside the engine's
            // adjacency cone), so the Right swipe was being silently consumed.
            // Same idiom as `TVTopMenuDownHandler` (onMoveCommand + @FocusState).
            .onMoveCommand { direction in moveFromLibrary(library, direction) }
            // Report this row's top in the level-1 HStack's coordinate space so
            // the flyout can align with the anchored row (§5.3). This survives
            // the panel's ScrollView / nested stacks, which a custom
            // VerticalAlignment guide would not.
            .background(libraryRowTopReporter(for: library))
            .accessibilityLabel(accessibilityLabel(for: library, isCurrent: isCurrent))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        } else {
            label
                .background(libraryRowTopReporter(for: library))
                .accessibilityLabel(accessibilityLabel(for: library, isCurrent: isCurrent))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
        }
    }

    private func libraryRowTopReporter(for library: Library) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TVCascadeRowAnchorKey.self,
                value: [library.id: geo.frame(in: .named(Self.cascadeSpace)).minY]
            )
        }
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
        .modifier(TVSkylinePanelChrome(
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
            .modifier(TVSkylinePanelChrome(
                cornerRadius: ContinuumTheme.Skyline.flyoutCornerRadius
            ))
            // A sibling focus section so vertical d-pad rolls the section list.
            // The Left move back to the library column is driven explicitly by
            // `moveFromSection` (onMoveCommand + @FocusState), not geometry.
            .focusSection()
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

    @ViewBuilder
    private func sectionRow(_ pill: TVLibraryPill, in library: Library) -> some View {
        let isFocused = focus == .section(library.id, pill)
        let label = TVCascadeSectionRowLabel(
            title: pill.title,
            systemImage: pill.systemImage,
            isFocused: isFocused
        )

        if entersPanel {
            Button {
                onCommitSection(library, pill)
            } label: {
                label
            }
            .buttonStyle(.continuumFlat)
            .focused($focus, equals: .section(library.id, pill))
            // A d-pad Left returns to the anchored library row explicitly
            // (claims it via @FocusState) rather than landing on whichever row
            // is geometrically nearest the offset flyout.
            .onMoveCommand { direction in moveFromSection(library, direction) }
            .accessibilityLabel("\(pill.title), section")
        } else {
            label
                .accessibilityLabel("\(pill.title), section")
        }
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
        guard entersPanel, token > 0, token != lastAppliedEntryToken else {
            tvFocusCascadeLog.debug("cascade.applyEntryToken SKIP token=\(token) entersPanel=\(self.entersPanel) lastApplied=\(self.lastAppliedEntryToken)")
            return
        }
        tvFocusCascadeLog.debug("cascade.applyEntryToken APPLY token=\(token) single=\(self.isSingleLibrary) scope=\(String(describing: self.currentScopeId), privacy: .public)")
        lastAppliedEntryToken = token
        if isSingleLibrary, let library = libraries.first {
            // Single-level: land on the first section (§5.3).
            focus = .section(library.id, pills.first ?? .recommended)
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
        tvFocusCascadeLog.debug("cascade.focus -> \(String(describing: newValue), privacy: .public)")
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
        if isCurrent { label += ", current library" }
        return label
    }

    // MARK: - Cross-column moves (§5.3 Right/Left)

    /// D-pad on a focused library row. **Right** crosses into that library's
    /// section flyout by claiming its first section through `@FocusState`,
    /// which overrides the focus engine — so it works regardless of the
    /// flyout's offset geometry (the move the engine kept silently dropping).
    /// Up/Down are left to the engine (additive: the closure runs alongside
    /// the engine's own move, so vertical rolling of the list still works).
    private func moveFromLibrary(_ library: Library, _ direction: MoveCommandDirection) {
        guard direction == .right else { return }
        tvFocusCascadeLog.debug("cascade.moveFromLibrary RIGHT lib=\(library.id, privacy: .public)")
        // Anchor the flyout to this library *now* (cancel the follow debounce)
        // so its section rows are mounted before we claim one.
        flyoutFollowTask?.cancel()
        flyoutAnchorId = library.id
        focus = .section(library.id, pills.first ?? .recommended)
    }

    /// D-pad on a focused section row. **Left** returns to this library's row
    /// in the level-1 column (claimed explicitly so it lands on the anchored
    /// library, not whichever row is geometrically nearest the offset flyout).
    private func moveFromSection(_ library: Library, _ direction: MoveCommandDirection) {
        guard direction == .left else { return }
        tvFocusCascadeLog.debug("cascade.moveFromSection LEFT lib=\(library.id, privacy: .public)")
        focus = .library(library.id)
    }
}

// MARK: - Row labels

/// Level-1 library row (§5.3): icon — name — trailing glyph. Inverts to
/// white on focus, matching the bar/pill grammar.
private struct TVCascadeLibraryRowLabel: View {
    let title: String
    let systemImage: String
    let trailingGlyph: String
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: ContinuumTheme.Skyline.cascadeRowIconSize)

            Text(title)
                .font(.system(size: ContinuumTheme.Skyline.cascadeRowTextSize, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 12)

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
        // Reduce Motion snaps the cascade row inversion (§4.2 acceptance).
        .animation(reduceMotion ? nil : ContinuumTheme.springAnimation, value: isFocused)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Reduce Motion snaps the flyout row inversion (§4.2 acceptance).
        .animation(reduceMotion ? nil : ContinuumTheme.springAnimation, value: isFocused)
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
