import SwiftUI

// MARK: - Aurora palette
//
// The "Aurora" first-run direction: a warm, cinematic skin layered on the
// existing Skyline tokens. Warm off-white ink instead of pure grey, a single
// champagne-gold accent, and a deep plum night base behind the aurora
// backdrop. These live alongside the Continuum palette and skin the first-run
// flow (server → sign-in → profile) across iOS, tvOS, and macOS.

extension Color {
    /// Warm off-white primary text (#F3EFE9) — replaces #EDEDED for the Aurora flow.
    static let auroraInk = Color(hex: "#F3EFE9")
    /// Champagne-gold accent (#F3D3A0) — eyebrows, hairlines, focus glow, wordmark dot.
    static let auroraAccent = Color(hex: "#F3D3A0")
    /// Deep plum night sky, top → bottom.
    static let auroraNightTop = Color(hex: "#1C1329")
    static let auroraNightMid = Color(hex: "#0D0A17")
    static let auroraNightBottom = Color(hex: "#070509")
    /// Dark glass tint laid over the material blur.
    static let auroraGlassTint = Color(hex: "#171019")

    static var auroraInkSecondary: Color { auroraInk.opacity(0.62) }
    static var auroraInkTertiary: Color { auroraInk.opacity(0.40) }
}

// MARK: - Eyebrow (gold hairline + mono caps label)

struct AuroraEyebrow: View {
    let text: String
    var centered: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color.auroraAccent, Color.auroraAccent.opacity(0)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 46, height: 1)
            Text(text.uppercased())
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .tracking(3.5)
                .foregroundStyle(Color.auroraAccent)
        }
        .frame(maxWidth: centered ? .infinity : nil)
    }
}

// MARK: - Liquid glass panel

struct AuroraGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 28
    var emphasized: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.auroraGlassTint.opacity(0.5))
                    )
            }
            .overlay {
                // gradient hairline border
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderGradient, lineWidth: 1)
            }
            .overlay {
                // top sheen
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.10), .clear],
                        center: .top, startRadius: 0, endRadius: 440))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .background {
                // soft gold halo for the recommended card
                if emphasized {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.auroraAccent.opacity(0.16))
                        .blur(radius: 26)
                        .padding(-6)
                }
            }
            .shadow(color: .black.opacity(0.75), radius: 60, x: 0, y: 40)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: emphasized
                ? [Color.auroraAccent.opacity(0.6), Color.auroraAccent.opacity(0.16), .white.opacity(0.04)]
                : [.white.opacity(0.34), .white.opacity(0.06), .white.opacity(0.02)],
            startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    func auroraGlass(cornerRadius: CGFloat = 28, emphasized: Bool = false) -> some View {
        modifier(AuroraGlassPanel(cornerRadius: cornerRadius, emphasized: emphasized))
    }
}

// MARK: - Primary button (warm cream pill + gold focus glow)

struct AuroraPrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        AuroraPrimaryBody(configuration: configuration, isLoading: isLoading)
    }
}

private struct AuroraPrimaryBody: View {
    let configuration: ButtonStyle.Configuration
    let isLoading: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(Color(hex: "#20160A"))
                    .scaleEffect(0.8)
            }
            configuration.label
        }
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(Color(hex: "#20160A"))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 30)
        .background(
            RoundedRectangle(cornerRadius: AuroraControl.corner, style: .continuous).fill(LinearGradient(
                colors: [Color(hex: "#FDF7EC"), Color(hex: "#F1E3CD")],
                startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraControl.corner, style: .continuous)
                .stroke(.white, lineWidth: isFocused ? 3 : 0)
        )
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: AuroraControl.corner, style: .continuous)
                    .stroke(Color.auroraAccent.opacity(0.55), lineWidth: 8)
                    .padding(-5)
                    .blur(radius: 8)
            }
        }
        .scaleEffect(isFocused && !reduceMotion ? 1.05 : 1.0)
        .shadow(
            color: isFocused ? Color.auroraAccent.opacity(0.5) : .black.opacity(0.45),
            radius: isFocused ? 26 : 16, y: 8)
        .opacity(configuration.isPressed ? 0.85 : 1.0)
        .focusEffectDisabled()
        .animation(ContinuumTheme.springAnimation, value: isFocused)
    }
}

// MARK: - Ghost button (tertiary — "Use a password instead")

struct AuroraGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AuroraGhostBody(configuration: configuration)
    }
}

private struct AuroraGhostBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    // tvOS uses 10-foot sizing; iOS/macOS need a normal tertiary-button scale.
    #if os(tvOS)
    private let fontSize: CGFloat = 22
    private let hPadding: CGFloat = 22
    private let vPadding: CGFloat = 12
    #else
    private let fontSize: CGFloat = 15
    private let hPadding: CGFloat = 16
    private let vPadding: CGFloat = 9
    #endif

    var body: some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(isFocused ? Color.auroraNightBottom : Color.auroraInkSecondary)
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? Color.auroraInk : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isFocused ? .white : .white.opacity(0.14),
                            lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .focusEffectDisabled()
            .animation(ContinuumTheme.springAnimation, value: isFocused)
    }
}

// MARK: - Numbered "how-to" step row

struct AuroraStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("\(number)")
                .font(.system(size: 21, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.auroraAccent)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.auroraAccent.opacity(0.16)))
                .overlay(Circle().stroke(Color.auroraAccent.opacity(0.34), lineWidth: 1))
            Text(text)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Color.auroraInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared control metrics

enum AuroraControl {
    /// Shared height for inputs + segmented options so they line up on a row.
    #if os(tvOS)
    static let height: CGFloat = 72
    #else
    static let height: CGFloat = 52
    #endif
    static let corner: CGFloat = 14
    /// Warm cream fill used when a field/segment is focused.
    static let activeFill = Color(hex: "#F4EEE2")
    static let activeInk = Color(hex: "#1A1206")
    static let activePlaceholder = Color(hex: "#4A4035")
}

// MARK: - Aurora segmented option (equal-width, single-line chip)

struct AuroraSegment: View {
    let title: String
    let isSelected: Bool
    let isFocused: Bool
    var height: CGFloat = AuroraControl.height

    var body: some View {
        Text(title)
            .font(.system(size: 21, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: AuroraControl.corner, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraControl.corner, style: .continuous)
                    .stroke(stroke, lineWidth: 1.5)
            )
            .animation(ContinuumTheme.springAnimation, value: isFocused)
    }

    private var textColor: Color {
        if isFocused { return AuroraControl.activeInk }
        return isSelected ? Color.auroraInk : Color.auroraInkSecondary
    }
    private var fill: Color {
        if isFocused { return AuroraControl.activeFill }
        return isSelected ? Color.auroraAccent.opacity(0.18) : Color.white.opacity(0.06)
    }
    private var stroke: Color {
        if isFocused { return .clear }
        return isSelected ? Color.auroraAccent.opacity(0.5) : Color.white.opacity(0.14)
    }
}
