#if os(tvOS)
import SwiftUI

struct TVLibrarySelectionRequest: Equatable {
    let libraryID: Int
    let token: Int
}

/// Root of the Libraries tab on tvOS. Owns the library list + active library
/// selection, then delegates to `TVLibraryGridView` for the actual browse
/// experience.
///
/// This replaces the shared iOS `LibrariesTabView` on the tvOS target. The
/// iOS view ships a Plex-style 3-subtab UI (Recommended / Library / Collections)
/// which was designed for touch + swipe — on a 10-foot remote it collapses
/// into a cramped pill stack with tiny poster tiles. The tvOS version instead:
///
/// - Drops subtabs for Phase 1 (focus straight on the grid — collections and
///   recommended come back in Phase 2 as a filter-landing page)
/// - Moves library-switching into a focus-friendly full-screen picker
/// - Defers all catalog rendering to `TVLibraryGridView` which is purpose-
///   built for 100k+ items
struct TVLibrariesTabView: View {
    @Binding var selectedMode: TVLibraryLandingMode
    @Binding var headerContext: TVLibraryHeaderContext?
    let librarySelectionRequest: TVLibrarySelectionRequest?
    var focusRequest: Int = 0
    var isTopMenuFocused: Bool = false
    let onTopMenuFocusRequest: (() -> Void)?

    @State private var libraries: [Library] = []
    @State private var selectedLibraryId: Int?
    @State private var isLoading = true
    @State private var error: ErrorState?

    @AppStorage("librariesTabSelectedLibraryId") private var storedLibraryId: Int = 0

    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let activeLibrary {
                content(activeLibrary: activeLibrary)
            } else if let error, libraries.isEmpty {
                ErrorView(state: error, onRetry: { Task { await loadLibraries() } })
                    .padding(.top, TVTopMenuLayout.contentTopInset)
            } else if isLoading && libraries.isEmpty {
                Color.clear
                    .padding(.top, TVTopMenuLayout.contentTopInset)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "No libraries available",
                    subtitle: "Libraries visible to this profile will appear here."
                )
                .padding(.top, TVTopMenuLayout.contentTopInset)
            }
        }
        .continuumBackground()
        .task {
            await loadLibraries()
        }
        .onChange(of: librarySelectionRequest) { _, request in
            guard let request else { return }
            selectLibrary(request.libraryID)
        }
        .onDisappear {
            headerContext = nil
        }
    }

    // MARK: - Content

    /// The landing page owns its own artwork-first layout; library switching
    /// and the Recommended/Collections mode control live in the app header.
    @ViewBuilder
    private func content(activeLibrary: Library) -> some View {
        TVLibraryLandingView(
            library: activeLibrary,
            selectedMode: $selectedMode,
            focusRequest: focusRequest,
            isTopMenuFocused: isTopMenuFocused,
            onTopMenuFocusRequest: onTopMenuFocusRequest
        )
        // Re-create the landing page when switching libraries so its
        // filters + section fetch reset cleanly.
        .id(activeLibrary.id)
        .onAppear {
            updateHeaderContext(activeLibrary: activeLibrary)
        }
    }

    // MARK: - Data

    private var activeLibrary: Library? {
        libraries.first(where: { $0.id == selectedLibraryId })
    }

    private func loadLibraries() async {
        isLoading = true
        error = nil
        do {
            let response: LibrariesResponse = try await ContinuumAPI.shared.get("/api/v1/user/libraries")
            libraries = response.libraries

            let restored = storedLibraryId != 0
                ? libraries.first(where: { $0.id == storedLibraryId })?.id
                : nil
            let resolved = restored ?? libraries.first?.id
            selectedLibraryId = resolved
            if let resolved { storedLibraryId = resolved }
            updateHeaderContext()
        } catch {
            self.error = ErrorState(error)
            headerContext = nil
        }
        isLoading = false
    }

    private func selectLibrary(_ id: Int) {
        guard libraries.contains(where: { $0.id == id }) else { return }
        selectedLibraryId = id
        storedLibraryId = id
        updateHeaderContext()
    }

    private func updateHeaderContext() {
        guard let activeLibrary else {
            headerContext = nil
            return
        }
        updateHeaderContext(activeLibrary: activeLibrary)
    }

    private func updateHeaderContext(activeLibrary: Library) {
        headerContext = TVLibraryHeaderContext(
            id: activeLibrary.id,
            name: activeLibrary.name,
            typeLabel: libraryTypeLabel(for: activeLibrary),
            iconName: libraryIconName(for: activeLibrary),
            canSwitchLibrary: libraries.count > 1,
            options: libraries.map { library in
                TVLibraryMenuOption(
                    id: library.id,
                    name: library.name,
                    typeLabel: libraryTypeLabel(for: library),
                    iconName: libraryIconName(for: library)
                )
            }
        )
    }

    private func libraryTypeLabel(for library: Library) -> String {
        if library.isAudiobookLibrary { return "Audiobooks" }
        if library.isSeriesLibrary { return "TV Shows" }
        if library.type == "movies" { return "Movies" }
        if library.type == "music" { return "Music" }
        return "Library"
    }

    private func libraryIconName(for library: Library) -> String {
        if library.isAudiobookLibrary { return "book.closed.fill" }
        if library.isSeriesLibrary { return "tv.fill" }
        if library.type == "movies" { return "film.fill" }
        if library.type == "music" { return "music.note" }
        return "square.stack.3d.up.fill"
    }
}

// MARK: - Library picker (tvOS-specific)

/// Full-screen library picker, restyled to feel like Apple's own tvOS
/// confirmation sheets. Everything that distinguished the previous
/// revision from a native sheet — radial wash backdrop, huge 64pt
/// heavy title, subtitle prompt, pinned Close pill, custom row border
/// treatment — has been swapped for Apple's simpler patterns:
///
/// - Dimmed black backdrop (no gradient), like Apple's alert overlays
/// - Single 40pt semibold title, no tagline
/// - Narrow centered column of rows (~680pt max width)
/// - Rows invert on focus (white background, black text) — the default
///   tvOS card grammar — with a soft shadow lift
/// - Menu button dismisses via `.onExitCommand`; no visible Close
///   button competing for focus. A tiny "Press Menu to cancel" hint
///   sits at the bottom so the interaction stays discoverable.
private struct TVLibraryPicker: View {
    let libraries: [Library]
    let selectedLibraryId: Int?
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Flat dark dim — Apple TV's confirmation / picker sheets
            // don't use gradient washes.
            Color.black.opacity(0.82).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Switch Library")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 140)
                    .padding(.bottom, 36)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(libraries) { library in
                            TVLibraryPickerRow(
                                library: library,
                                isSelected: library.id == selectedLibraryId,
                                onTap: { onSelect(library.id) }
                            )
                        }
                    }
                    .frame(maxWidth: 680)
                    // Horizontal inset so the 1.04 focus scale + shadow
                    // aren't clipped by the ScrollView's bounds. Without
                    // this, focused rows lose their rounded corners on
                    // the left/right edges and read as squares.
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()

                Spacer(minLength: 0)

                Text("Press Menu to cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand { onDismiss() }
    }
}

/// Single row in the library picker. Uses Apple TV's native focus
/// grammar (white background + black text on focus, subtle lift via
/// shadow and scale) rather than a custom border treatment.
private struct TVLibraryPickerRow: View {
    let library: Library
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(library.name)
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(1)

                    Text(typeLabel)
                        .font(.system(size: 15, weight: .medium))
                        .opacity(0.6)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TVLibraryPickerRowStyle())
    }

    // MARK: - Copy

    private var icon: String {
        if library.isAudiobookLibrary { return "book.closed.fill" }
        if library.isSeriesLibrary { return "tv.fill" }
        if library.type == "movies" { return "film.fill" }
        if library.type == "music" { return "music.note" }
        return "square.stack.3d.up.fill"
    }

    private var typeLabel: String {
        if library.isAudiobookLibrary { return "Audiobooks library" }
        if library.isSeriesLibrary { return "TV library" }
        if library.type == "movies" { return "Movies library" }
        if library.type == "music" { return "Music library" }
        return "Library"
    }
}

// MARK: - Row button style (native inversion)

/// ButtonStyle for the picker rows. Mirrors Apple TV's native list
/// focus grammar: white fill + black text on focus, tiny resting
/// translucent fill so selected rows don't float on a pure-black
/// backdrop, and a soft shadow lift instead of a stroked border ring.
private struct TVLibraryPickerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVLibraryPickerRowBody(configuration: configuration)
    }
}

private struct TVLibraryPickerRowBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(isFocused ? .black : .white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.08))
            )
            .shadow(
                color: isFocused ? .black.opacity(0.45) : .clear,
                radius: isFocused ? 20 : 0,
                y: isFocused ? 10 : 0
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
#endif
