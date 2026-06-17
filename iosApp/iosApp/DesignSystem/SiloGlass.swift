import SwiftUI

extension View {
    /// Silo's Liquid Glass background in `shape`. All Apple targets (iOS / macOS /
    /// tvOS) are at the 26 minimum, so this is unconditional. It's the single
    /// place glass styling is configured — call sites never write `glassEffect`
    /// directly so tint/shape conventions stay consistent.
    func siloGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return self.glassEffect(glass, in: shape)
    }
}
