import SwiftUI

/// Visual corner picker: a small 2:3 poster shape with a tappable target
/// at each of the four corners. The selected corner is filled; others
/// render as outline rings. Replaces the text-only "Top Left / Top Right
/// / …" dropdown with a glanceable spatial picker.
///
/// Two surfaces consume this:
/// - iOS: inline disclosure under an overlay row.
/// - tvOS: inside the per-overlay detail sheet, where each corner is a
///   focusable button with a custom focus visual (brighten + ring + lift).
///   The app suppresses the default tvOS halo, so each dot renders its own
///   focus state rather than relying on the platform.
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

            // Position each dot via a transparent full-size host + corner
            // alignment, so the focusable Button stays the size of the dot.
            // Sizing the Button itself to the whole grid (the previous
            // approach) left four mutually-overlapping focus targets the
            // engine couldn't disambiguate by direction.
            ForEach(OverlayPosition.allCases, id: \.rawValue) { position in
                Color.clear
                    .frame(width: width, height: height)
                    .overlay(alignment: anchor(for: position)) {
                        cornerDot(position)
                            .padding(insetMargin)
                    }
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
            // The dot is rendered by the style so it can react to focus; the
            // label just establishes the focusable/hit region size.
            Color.clear.frame(width: dotSize, height: dotSize)
        }
        .buttonStyle(OverlayCornerDotStyle(selected: selected, accent: accent, dotSize: dotSize))
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

/// Corner-dot button style. Renders the dot from `selected` + focus state so a
/// focused-but-unselected corner is clearly visible (the previous `.plain`
/// style drew only the selection state and showed no focus on tvOS).
private struct OverlayCornerDotStyle: ButtonStyle {
    let selected: Bool
    let accent: Color
    let dotSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        OverlayCornerDot(
            selected: selected,
            accent: accent,
            dotSize: dotSize,
            isPressed: configuration.isPressed
        )
    }
}

private struct OverlayCornerDot: View {
    let selected: Bool
    let accent: Color
    let dotSize: CGFloat
    let isPressed: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(fillColor)
            .overlay(
                Circle().stroke(strokeColor, lineWidth: strokeWidth)
            )
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(scale)
            .opacity(isPressed ? 0.7 : 1.0)
            #if os(tvOS)
            .focusEffectDisabled()
            #endif
            .animation(.easeOut(duration: 0.15), value: selected)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: isPressed)
    }

    private var fillColor: Color {
        if selected { return accent }
        if isFocused { return Color.white.opacity(0.55) }
        return Color.white.opacity(0.18)
    }

    private var strokeColor: Color {
        if isFocused || selected { return .white }
        return Color.white.opacity(0.35)
    }

    private var strokeWidth: CGFloat {
        if isFocused { return 3 }
        return selected ? 2 : 1
    }

    private var scale: CGFloat {
        // Under Reduce Motion the focus lift is dropped; the white fill +
        // 3pt stroke still mark the focused dot.
        let focusScale: CGFloat = reduceMotion ? 1.0 : 1.3
        let base: CGFloat = isFocused ? focusScale : (selected ? 1.0 : 0.8)
        return isPressed ? base * 0.94 : base
    }
}
