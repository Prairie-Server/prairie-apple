import SwiftUI

/// Size-class-aware poster grid columns.
///
/// iPhone portrait and iPad in narrow split view report `.compact` and get
/// 3 columns — matching the original iPhone-only layout. iPad full-screen
/// and landscape report `.regular` and get 5 columns, so posters render at
/// their intended density instead of stretching to nearly 2× width.
///
/// tvOS views use their own hand-tuned column counts (see `TVCatalogGrid`)
/// and don't consume this helper.
enum AdaptiveColumns {
    static func posters(
        for sizeClass: UserInterfaceSizeClass?,
        spacing: CGFloat = 12
    ) -> [GridItem] {
        let count = (sizeClass == .regular) ? 5 : 3
        return Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: count
        )
    }
}

extension View {
    /// Caps form/content width so text fields and buttons don't stretch
    /// edge-to-edge on iPad. iPhones are already narrower than the cap, so
    /// this is a no-op on phone. The second `frame` centers the capped view.
    func continuumFormWidth(_ maxWidth: CGFloat = 600) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

