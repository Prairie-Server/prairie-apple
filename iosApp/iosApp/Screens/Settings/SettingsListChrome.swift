#if !os(tvOS)
import SwiftUI

extension View {
    func settingsListChrome() -> some View {
        prairieGroupedListStyle()
            .prairieScrollContentBackgroundHidden()
            .background(SettingsBackdrop())
    }
}
#endif
