#if os(iOS)
import SwiftUI

struct SettingsOverviewDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.prairieDivider)
            .padding(.leading, 66)
    }
}
#endif
