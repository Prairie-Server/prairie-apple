#if os(tvOS)
import SwiftUI

/// Full-screen, focus-friendly filter chooser for a single library.
///
/// Hosts the Sort / Decade / Genre pickers that used to sit on the primary
/// landing page. They were demoted here so the landing can lead with artwork
/// (Continue Watching, Recently Added, etc.) and keep this "browse by facet"
/// flow one Menu-button press away without dominating the surface.
///
/// Every selection dismisses the sheet and hands a fully-built
/// `TVLibraryFilter` back up to the landing, which pushes the grid.
struct TVLibraryFilterSheet: View {
    let library: Library
    let filters: CatalogFilters?
    let isLoadingFilters: Bool
    let onSelect: (TVLibraryFilter, String?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            // Soft off-center radial wash so the sheet reads as its own space,
            // not a flat black over the landing. Monochrome — no brand tint.
            RadialGradient(
                colors: [
                    Color.continuumOnSurface.opacity(0.05),
                    Color.continuumBackground,
                ],
                center: .init(x: 0.25, y: 0.1),
                startRadius: 80,
                endRadius: 1400
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 60) {
                    header

                    sortRail
                    decadeRail
                    genreSection
                }
                .padding(.vertical, 80)
            }

            // Back / dismiss hint — pinned top-right. tvOS Menu button also
            // dismisses, but focus-users appreciate a visible target.
            VStack {
                HStack {
                    Spacer()
                    dismissButton
                }
                Spacer()
            }
            .padding(.horizontal, ContinuumTheme.safePadding)
            .padding(.top, 40)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter & Sort")
                .font(.system(size: 64, weight: .heavy))
                .foregroundColor(.continuumOnSurface)

            Text(library.name)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.continuumSecondaryText)
        }
        .padding(.horizontal, ContinuumTheme.safePadding)
    }

    // MARK: - Sort

    private var sortRail: some View {
        TVChipRail(
            title: "Sort By",
            items: [
                TVChipItem(id: "added_at", label: "Recently Added"),
                TVChipItem(id: "title", label: "A–Z"),
                TVChipItem(id: "release_date", label: "Release Date"),
                TVChipItem(id: "rating_imdb", label: "Rating"),
            ],
            onSelect: { chip in
                var filter = TVLibraryFilter.none
                filter.sort = chip.id
                onSelect(filter, "Sorted by \(chip.label)")
            }
        )
    }

    // MARK: - Decades

    private var decadeRail: some View {
        TVChipRail(
            title: "Decade",
            items: decades.map { TVChipItem(id: "\($0.min)-\($0.max)", label: $0.label) },
            onSelect: { chip in
                guard let decade = decades.first(where: { "\($0.min)-\($0.max)" == chip.id }) else { return }
                var filter = TVLibraryFilter.none
                filter.yearMin = decade.min
                filter.yearMax = decade.max
                onSelect(filter, decade.label)
            }
        )
    }

    private var decades: [Decade] {
        [
            Decade(label: "2020s", min: 2020, max: 2029),
            Decade(label: "2010s", min: 2010, max: 2019),
            Decade(label: "2000s", min: 2000, max: 2009),
            Decade(label: "1990s", min: 1990, max: 1999),
            Decade(label: "1980s", min: 1980, max: 1989),
            Decade(label: "Classics", min: 1900, max: 1979),
        ]
    }

    // MARK: - Genres

    @ViewBuilder
    private var genreSection: some View {
        if isLoadingFilters {
            HStack {
                Spacer()
                ProgressView().tint(.continuumOnSurface)
                Spacer()
            }
            .padding(.vertical, 32)
        } else if let genres = filters?.genres, !genres.isEmpty {
            TVGenreRail(genres: genres) { genre in
                var filter = TVLibraryFilter.none
                filter.genre = genre
                onSelect(filter, genre)
            }
        }
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 12) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                Text("Close")
                    .font(.continuumHeadline)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Models

private struct Decade {
    let label: String
    let min: Int
    let max: Int
}
#endif
