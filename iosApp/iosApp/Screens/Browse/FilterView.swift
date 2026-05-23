import SwiftUI

/// Sheet for selecting browse filters — Plezy style.
/// Pill chips: selected = white bg/dark text, unselected = surface bg/muted text.
struct FilterView: View {
    @Binding var selectedGenre: String?
    @Binding var sortBy: String
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let genres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime",
        "Documentary", "Drama", "Family", "Fantasy", "History",
        "Horror", "Music", "Mystery", "Romance", "Science Fiction",
        "Thriller", "War", "Western"
    ]

    private let sortOptions = [
        ("title", "Title"),
        ("year", "Year"),
        ("rating", "Rating"),
        ("added", "Recently Added")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ContinuumTheme.largePadding) {
                    sortSection
                    genreSection
                }
                .padding(ContinuumTheme.padding)
            }
            .continuumBackground()
            .navigationTitle("Filters")
            .continuumNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        selectedGenre = nil
                        sortBy = "title"
                    }
                    .foregroundColor(.continuumSecondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                    .foregroundColor(.continuumOnSurface)
                }
            }
            .continuumNavigationBarSurfaceBackground()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sort Section

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sort By")
                .font(.continuumHeadline)
                .foregroundColor(.continuumOnSurface)

            FlowLayout(spacing: 8) {
                ForEach(sortOptions, id: \.0) { value, label in
                    chipButton(label: label, isSelected: sortBy == value) {
                        sortBy = value
                    }
                }
            }
        }
    }

    // MARK: - Genre Section

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Genre")
                .font(.continuumHeadline)
                .foregroundColor(.continuumOnSurface)

            FlowLayout(spacing: 8) {
                chipButton(label: "All", isSelected: selectedGenre == nil) {
                    selectedGenre = nil
                }

                ForEach(genres, id: \.self) { genre in
                    chipButton(label: genre, isSelected: selectedGenre == genre) {
                        selectedGenre = genre
                    }
                }
            }
        }
    }

    // MARK: - Chip (Plezy: selected = inverted white/black, unselected = surface/muted)

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.continuumCaption)
                .foregroundColor(isSelected ? Color.continuumBackground : .continuumSecondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.continuumOnSurface : Color.continuumSurfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowLayout

/// Simple wrapping layout for filter chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return LayoutResult(
            size: CGSize(width: maxX, height: y + rowHeight),
            positions: positions
        )
    }
}
