import SwiftUI

extension View {
    /// Silo's Liquid Glass background in `shape`.
    ///
    /// iOS (min 26): always real `glassEffect`. macOS (min 15): `glassEffect` on
    /// macOS 26+, `.ultraThinMaterial` fallback below. This is the ONLY place the
    /// availability decision lives — call sites never write `#available` for glass.
    ///
    /// When macOS min reaches 26.0, delete the `#if os(macOS)` fallback branch and
    /// this becomes a one-liner over `glassEffect`.
    @ViewBuilder
    func siloGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if os(macOS)
        if #available(macOS 26, *) {
            self.glassEffect(siloGlassConfig(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.glassEffect(siloGlassConfig(tint: tint, interactive: interactive), in: shape)
        #endif
    }
}

@available(iOS 26, macOS 26, *)
private func siloGlassConfig(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}
