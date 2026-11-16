import SwiftUI

struct PersonalListNavigationChrome: ViewModifier {
    let title: LocalizedStringResource?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(Text(title))
                .prairieNavigationTitleDisplayMode(.large)
        } else {
            content
        }
    }
}
