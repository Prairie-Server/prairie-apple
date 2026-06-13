#if os(tvOS)
import SwiftUI

/// `Genres` pill content of a library tab: a cloud of capsule chips, one
/// per genre the scoped library actually contains (Skyline §6.4). Picking
/// a genre pushes the standard library grid filtered to it — the existing
/// `.tvLibraryGrid` route — so Menu/Back returns here with focus intact.
struct TVLibraryGenresView: View {
    let library: Library

    @State private var genres: [String] = []
    @State private var isLoading = true
    @State private var error: ErrorState? = nil

    @Environment(AppRouter.self) private var router

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 20, alignment: .leading)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: ContinuumTheme.Skyline.libraryContentTopInset)

                chipCloud
            }
            .padding(.bottom, ContinuumTheme.largePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard genres.isEmpty else { return }
            await loadGenres()
        }
    }

    @ViewBuilder
    private var chipCloud: some View {
        if isLoading && genres.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 300)
        } else if let error, genres.isEmpty {
            ErrorView(state: error, onRetry: { Task { await loadGenres() } })
        } else if genres.isEmpty {
            EmptyStateView(
                icon: "tag",
                title: "No genres yet",
                subtitle: "Genres from this library's metadata will appear here."
            )
            .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(genres, id: \.self) { genre in
                    chipButton(genre)
                }
            }
            .padding(.horizontal, ContinuumTheme.Skyline.safeAreaX)
            .focusSection()
        }
    }

    private func chipButton(_ genre: String) -> some View {
        Button {
            router.navigate(to: .tvLibraryGrid(
                libraryId: library.id,
                libraryName: library.name,
                libraryType: library.type,
                filter: TVLibraryFilterPayload(genre: genre),
                subtitle: genre
            ))
        } label: {
            Text(genre)
                .font(.system(size: ContinuumTheme.Skyline.pillLabelSize, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ContinuumTheme.Skyline.pillPaddingHorizontal)
                .padding(.vertical, 16)
        }
        .buttonStyle(TVGenreChipButtonStyle())
        .accessibilityLabel(genre)
    }

    // MARK: - Data

    private func loadGenres() async {
        isLoading = true
        error = nil
        do {
            let filters = try await ContinuumAPI.shared.catalogFilters(libraryId: library.id)
            genres = filters.genres
        } catch let err {
            error = ErrorState(err)
        }
        isLoading = false
    }
}

/// Capsule chip grammar (§6.4): `chrome.unfocused-bg` at rest, inverted
/// white when focused — same focus language as the pill row above it.
private struct TVGenreChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVGenreChipButtonBody(configuration: configuration)
    }
}

private struct TVGenreChipButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.continuumBackground : .white.opacity(0.78))
            .background(
                Capsule().fill(isFocused ? Color.white : Color.continuumChromeRestingFill)
            )
            .overlay {
                Capsule().strokeBorder(
                    isFocused ? Color.clear : Color.continuumChromeRestingBorder,
                    lineWidth: 1
                )
            }
            // Reduce Motion drops the focus scale entirely so the chip
            // inversion snaps (§4.2 acceptance: no drift animations).
            .scaleEffect(isFocused && !reduceMotion ? 1.05 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .focusEffectDisabled()
            .animation(reduceMotion ? nil : ContinuumTheme.springAnimation, value: isFocused)
            .animation(reduceMotion ? nil : .easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }
}
#endif
