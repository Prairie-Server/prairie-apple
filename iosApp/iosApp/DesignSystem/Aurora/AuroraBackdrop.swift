import SwiftUI

// MARK: - Variants
//
// Each first-run screen gets its own aurora composition — where the light
// band sits, how warm/cool it is, and how bright — so the flow feels related
// but never identical, while staying within one plum-night palette.

struct AuroraVariant {
    /// Band rotation, degrees.
    var rotation: Double
    /// Vertical center of the light band, as a fraction of screen height.
    var centerY: CGFloat
    /// Hue rotation applied to the ribbons (warm 0 → cooler negative).
    var hue: Angle
    /// Overall brightness multiplier for the light.
    var intensity: Double

    static let welcome = AuroraVariant(rotation: -12, centerY: 0.24, hue: .degrees(0), intensity: 0.92)
    static let server = AuroraVariant(rotation: -9, centerY: 0.32, hue: .degrees(-22), intensity: 0.55)
    static let connecting = AuroraVariant(rotation: -6, centerY: 0.30, hue: .degrees(-6), intensity: 0.70)
    static let signIn = AuroraVariant(rotation: -14, centerY: 0.22, hue: .degrees(8), intensity: 0.86)
    static let profile = AuroraVariant(rotation: -10, centerY: 0.27, hue: .degrees(-16), intensity: 0.66)
}

enum AuroraScrim {
    /// Strong darkening on the left for hero text laid directly on the art.
    case left
    /// Radial darkening at the edges so a centered glass card pops.
    case soft
    case none
}

// MARK: - Backdrop

struct AuroraBackdrop: View {
    var variant: AuroraVariant = .signIn
    var scrim: AuroraScrim = .soft

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(
                    colors: [.auroraNightTop, .auroraNightMid, .auroraNightBottom],
                    startPoint: .top, endPoint: .bottom)

                AuroraStarfield()
                    .opacity(0.7)
                    .frame(height: h * 0.62)
                    .frame(maxHeight: .infinity, alignment: .top)

                // warm key-light bloom
                RadialGradient(
                    colors: [Color(hex: "#FFDCA6").opacity(0.42 * variant.intensity), .clear],
                    center: UnitPoint(x: 0.7, y: variant.centerY - 0.03),
                    startRadius: 0, endRadius: max(w, h) * 0.55)
                    .blendMode(.screen)

                ribbons(w: w, h: h)
                    .blur(radius: 72)
                    .hueRotation(variant.hue)
                    .blendMode(.screen)
                    .opacity(variant.intensity)

                // vignette
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.6)],
                    center: .center, startRadius: h * 0.22, endRadius: h * 0.9)

                scrimView(w: w, h: h)

                // top scrim keeps the wordmark + step chrome legible over light
                LinearGradient(
                    colors: [Color.auroraNightBottom.opacity(0.66), .clear],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: w, height: h)
        }
        .background(Color.auroraNightBottom)
        .ignoresSafeArea()
    }

    // Three soft, wide light bands stacked around the band center, rotated as
    // one group. Heavy blur (applied by the caller) turns these into flowing
    // aurora light rather than hard capsules.
    private func ribbons(w: CGFloat, h: CGFloat) -> some View {
        let cy = h * variant.centerY
        return ZStack {
            ribbon(colors: [Color(hex: "#FFD9A4"), Color(hex: "#FF90A8"), Color(hex: "#C490FF")],
                   width: w * 1.7, height: 150)
                .offset(y: 0)
            ribbon(colors: [Color(hex: "#FFADC6"), Color(hex: "#9B8BFF")],
                   width: w * 1.7, height: 116)
                .offset(y: 96)
            ribbon(colors: [Color(hex: "#C6F0E2"), Color(hex: "#8FE7CF")],
                   width: w * 1.5, height: 92)
                .offset(y: -120)
                .opacity(0.7)
        }
        .rotationEffect(.degrees(variant.rotation))
        .frame(width: w, height: h)
        .offset(y: cy - h / 2)
    }

    private func ribbon(colors: [Color], width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(
                colors: [.clear] + colors + [.clear],
                startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: height)
    }

    @ViewBuilder
    private func scrimView(w: CGFloat, h: CGFloat) -> some View {
        switch scrim {
        case .left:
            LinearGradient(stops: [
                .init(color: Color.auroraNightBottom.opacity(0.9), location: 0),
                .init(color: Color.auroraNightBottom.opacity(0.55), location: 0.3),
                .init(color: .clear, location: 0.72),
            ], startPoint: .leading, endPoint: .trailing)
        case .soft:
            RadialGradient(
                colors: [.clear, Color.auroraNightBottom.opacity(0.72)],
                center: .center, startRadius: h * 0.18, endRadius: h * 0.95)
        case .none:
            Color.clear
        }
    }
}

// MARK: - Starfield

private struct AuroraStarfield: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed: 9_123_457)
            for _ in 0..<64 {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let r = CGFloat(rng.next()) * 1.6 + 0.4
                let o = rng.next() * 0.5 + 0.12
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(o)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
