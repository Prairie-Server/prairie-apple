#if os(tvOS)
import SwiftUI

// MARK: - Reusable chip rail

/// Horizontal focus-aware rail of short text chips. Used for decades, sort
/// orders, and any other flat filter list where we want medium-sized buttons
/// rather than full-bleed cards.
struct TVChipRail: View {
    let title: String
    let items: [TVChipItem]
    let onSelect: (TVChipItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.continuumOnSurface)
                .padding(.horizontal, ContinuumTheme.safePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items) { item in
                        TVChipButton(label: item.label, action: { onSelect(item) })
                    }
                }
                .padding(.horizontal, ContinuumTheme.safePadding)
                .padding(.vertical, 8)
            }
            .focusSection()
        }
    }
}

struct TVChipItem: Identifiable, Hashable {
    let id: String
    let label: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    init(_ label: String) {
        self.id = label
        self.label = label
    }
}

private struct TVChipButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 28, weight: .medium))
        }
        .buttonStyle(TVChipButtonStyle())
    }
}

/// Custom `ButtonStyle` for chip-shaped filter buttons. Owns all focus
/// appearance via `@Environment(\.isFocused)` — critical on tvOS, where
/// pairing `.buttonStyle(.plain)` with an external `@FocusState` still
/// lets the system paint its default white focus halo around the
/// button's bounds. A custom `ButtonStyle` fully suppresses that.
private struct TVChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVChipButtonBody(configuration: configuration)
    }
}

private struct TVChipButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundColor(isFocused ? .continuumBackground : .continuumOnSurface)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(isFocused ? Color.continuumOnSurface : Color.continuumSurfaceElevated)
            )
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: isFocused)
            .animation(.easeOut(duration: ContinuumTheme.fastDuration), value: configuration.isPressed)
    }
}

// MARK: - Genre card rail

/// Horizontal rail of large focusable genre cards. Source: the distinct
/// genres returned by `/api/v1/catalog/filters?library_id=X`. No counts are
/// shown because the server does not provide them.
struct TVGenreRail: View {
    let genres: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Genres")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.continuumOnSurface)
                .padding(.horizontal, ContinuumTheme.safePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(genres, id: \.self) { genre in
                        TVGenreCard(genre: genre, action: { onSelect(genre) })
                    }
                }
                .padding(.horizontal, ContinuumTheme.safePadding)
                .padding(.vertical, 16)
            }
            .focusSection()
        }
    }
}

private struct TVGenreCard: View {
    let genre: String
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Deterministic gradient keyed off the genre name so each
                // genre card has a stable color — no runtime randomness, no
                // flicker on re-layout.
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.55, brightness: 0.45),
                        Color(hue: hue, saturation: 0.35, brightness: 0.25),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Text(genre)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(20)
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: ContinuumTheme.cardCornerRadius))
        }
        .buttonStyle(.card)
        .focused($isFocused)
    }

    /// Map the genre's hash to a hue in [0,1). Stable per genre string.
    private var hue: Double {
        var hasher = Hasher()
        hasher.combine(genre)
        let raw = UInt(bitPattern: hasher.finalize())
        return Double(raw % 360) / 360.0
    }
}
#endif
