#if os(tvOS)
import SwiftUI

/// Body of a Skyline library-type tab (Movies / Series / Music /
/// Audiobooks): the sub-destination pill row plus the selected pill's
/// content. Receives the profile's libraries of its type from the shell.
///
/// This replaced the old "Libraries is a place" tab: there is no longer a
/// full-screen library picker — the type tab *is* the library, and the
/// pill row is the §5.2 replacement for the Recommended/Collections mode
/// slider. Pills commit on press, never on focus.
///
/// Focus zones (§7), top to bottom: top bar → pill row → content. The
/// pill row hands Up to the bar; content reaches the pill row either
/// geometrically or through the boundary hand-up fallback.
struct TVLibraryTypeTabView: View {
    let type: TVLibraryTabType
    /// Libraries of `type` visible to this profile, ordered by `sortOrder`.
    let libraries: [Library]
    /// The library this tab is currently scoped to (§3.1). Resolved by the
    /// shell from the persisted per-profile scope, or the first library on
    /// cold start. The cascade selector (§5.3) switches it.
    let activeLibrary: Library?
    /// Pill selection lives in the shell so it survives tab switches
    /// within a session (§8); cold start always lands on Browse.
    @Binding var selectedPill: TVLibraryPill
    /// Item count for the scoped library, if the shell could resolve one
    /// (the `Library` model carries none — §G). Drives the caption suffix.
    var scopeItemCount: Int? = nil
    var focusRequest: Int = 0
    var isTopMenuFocused: Bool = false
    let onTopMenuFocusRequest: (() -> Void)?

    /// Imperative kick into the pill row: tab entry while a grid pill is
    /// restored, and the content zone's boundary hand-up.
    @State private var pillRowFocusRequest = 0

    private var pills: [TVLibraryPill] { TVLibraryPill.set(for: type) }

    var body: some View {
        Group {
            if let activeLibrary {
                ZStack(alignment: .top) {
                    pillContent(for: activeLibrary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    TVLibraryPillRow(
                        pills: pills,
                        selected: selectedPill,
                        caption: scopeCaption,
                        focusRequest: pillRowFocusRequest,
                        onSelect: selectPill(_:),
                        onMoveUp: onTopMenuFocusRequest
                    )
                }
                // Re-create the tab body when the scoped library changes so
                // section fetches and grid state reset cleanly.
                .id(activeLibrary.id)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "No \(type.title.lowercased()) libraries",
                    subtitle: "Libraries visible to this profile will appear here."
                )
                .padding(.top, TVTopMenuLayout.contentTopInset)
            }
        }
        .continuumBackground()
        .onAppear { routeEntryFocus(focusRequest) }
        .onChange(of: focusRequest) { _, request in routeEntryFocus(request) }
    }

    /// Scope caption (§5.2): the active library's name, plus an item-count
    /// suffix when the shell could resolve one (e.g. `Theatrical · 1,284
    /// films`). The `Library` model carries no count, so the suffix is
    /// best-effort from the loaded grid total and is omitted — never
    /// fabricated — when unavailable (§G). No freshness timestamp exists in
    /// the models, so none is shown.
    private var scopeCaption: String? {
        guard let name = activeLibrary?.name else { return nil }
        guard let count = scopeItemCount, count > 0 else { return name }
        return "\(name) · \(count.formatted(.number)) \(countNoun(count))"
    }

    /// Type-appropriate noun for the count suffix.
    private func countNoun(_ count: Int) -> String {
        let plural = count != 1
        switch type {
        case .movies: return plural ? "films" : "film"
        case .series: return plural ? "shows" : "show"
        case .music: return plural ? "albums" : "album"
        case .audiobooks: return plural ? "books" : "book"
        }
    }

    @ViewBuilder
    private func pillContent(for library: Library) -> some View {
        switch selectedPill {
        case .browse:
            TVLibraryBrowseView(
                library: library,
                focusRequest: contentEntryFocusRequest,
                isTopMenuFocused: isTopMenuFocused,
                onMoveUp: focusPillRow,
                onSelectCollectionsPill: jumpToCollectionsPill
            )
        case .collections:
            TVLibraryCollectionsView(
                library: library,
                focusRequest: contentEntryFocusRequest,
                isTopMenuFocused: isTopMenuFocused,
                onMoveUp: focusPillRow
            )
        case .genres:
            TVLibraryGenresView(library: library)
        case .aToZ:
            TVLibraryGridView(
                libraryId: library.id,
                libraryName: library.name,
                libraryType: library.type,
                initialFilter: .none,
                showsHeader: false,
                showsAlphabetRail: true,
                topContentInset: ContinuumTheme.Skyline.libraryContentTopInset
            )
        case .recentlyAdded:
            TVLibraryGridView(
                libraryId: library.id,
                libraryName: library.name,
                libraryType: library.type,
                initialFilter: TVLibraryFilter(sort: "added"),
                showsHeader: false,
                showsAlphabetRail: false,
                topContentInset: ContinuumTheme.Skyline.libraryContentTopInset
            )
        }
    }

    // MARK: - Selection & focus routing

    /// Pills commit on press. Content below crossfades (§4.2) while focus
    /// stays on the pressed pill — the fresh content's own default-focus
    /// makes its first item the d-pad entry target, satisfying §7's
    /// "switching pill resets content focus to the first item" without
    /// moving focus mid-transition.
    private func selectPill(_ pill: TVLibraryPill) {
        guard pill != selectedPill else { return }
        withAnimation(.easeInOut(duration: ContinuumTheme.normalDuration)) {
            selectedPill = pill
        }
    }

    /// Shell entry tokens land on the selected pill's natural target:
    /// Browse/Collections claim their first content item; the grid and
    /// genre pills park focus on the pill row (their cards have no
    /// imperative-claim plumbing, and the row is never empty).
    private var contentEntryFocusRequest: Int {
        switch selectedPill {
        case .browse, .collections: return focusRequest
        case .genres, .aToZ, .recentlyAdded: return 0
        }
    }

    private func routeEntryFocus(_ request: Int) {
        guard request > 0 else { return }
        switch selectedPill {
        case .browse, .collections:
            break // content claims via its own forwarded token
        case .genres, .aToZ, .recentlyAdded:
            pillRowFocusRequest += 1
        }
    }

    private func focusPillRow() {
        pillRowFocusRequest += 1
    }

    /// The Browse landing's trailing `See All` card commits the
    /// Collections pill (§6.2). The pressed card disappears with the
    /// content swap, so focus is explicitly parked on the pill row —
    /// the stable "you are here" chrome — rather than left to the engine.
    private func jumpToCollectionsPill() {
        selectPill(.collections)
        pillRowFocusRequest += 1
    }
}
#endif
