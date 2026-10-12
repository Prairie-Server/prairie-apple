import SwiftUI

/// Plain canvas shared by the native Settings experiences, so grouped rows
/// and focus platters carry all of the contrast. Black on iOS and tvOS; the
/// Mac uses its page canvas so Settings matches every other page.
struct SettingsBackdrop: View {
    var body: some View {
        #if os(macOS)
        PrairiePageBackdrop()
        #else
        Color.prairieBackground
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #endif
    }
}
