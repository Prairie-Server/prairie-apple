import SwiftUI

/// Visual corner picker: a small 2:3 poster shape with a tappable target
/// at each of the four corners. The selected corner is filled; others
/// render as outline rings. Replaces the text-only "Top Left / Top Right
/// / …" dropdown with a glanceable spatial picker.
///
/// Two surfaces consume this:
/// - iOS: inline disclosure under an overlay row.
/// - tvOS: inside the per-overlay detail sheet, where each corner is a
///   focused button. Focus rings are supplied by the platform.
struct OverlayPositionGrid: View {
    @Binding var selection: OverlayPosition
    /// Color of the highlighted corner. Defaults to the system accent
    /// color so the picker visually picks up the parent theme.
    var accent: Color = .accentColor
    /// Size of the picker. Width controls the layout; height tracks 2:3.
    var width: CGFloat = 120

    private var height: CGFloat { width * 1.5 }
    private var dotSize: CGFloat { max(20, width * 0.22) }
    private var insetMargin: CGFloat { max(8, width * 0.10) }

    var body: some View {
        ZStack {
            // Poster silhouette so the picker reads as "a corner on a card".
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .frame(width: width, height: height)

            ForEach(OverlayPosition.allCases, id: \.rawValue) { position in
                cornerDot(position)
            }
        }
        .frame(width: width, height: height)
        .accessibilityRepresentation { picker }
    }

    private func cornerDot(_ position: OverlayPosition) -> some View {
        let selected = selection == position
        return Button {
            selection = position
        } label: {
            Circle()
                .fill(selected ? accent : Color.white.opacity(0.18))
                .overlay(
                    Circle().stroke(
                        selected ? .white : Color.white.opacity(0.35),
                        lineWidth: selected ? 2 : 1
                    )
                )
                .frame(width: dotSize, height: dotSize)
                .scaleEffect(selected ? 1.0 : 0.8)
                .animation(.easeOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height, alignment: anchor(for: position))
        .padding(insetMargin)
        .frame(width: width, height: height)
        .accessibilityLabel(position.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func anchor(for position: OverlayPosition) -> Alignment {
        switch position {
        case .topLeft:     return .topLeading
        case .topRight:    return .topTrailing
        case .bottomLeft:  return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    /// VoiceOver-friendly fallback so the picker reads as a 4-option
    /// segmented control rather than four separate dot buttons.
    private var picker: some View {
        Picker("Position", selection: $selection) {
            ForEach(OverlayPosition.allCases, id: \.rawValue) { pos in
                Text(pos.displayName).tag(pos)
            }
        }
    }
}
