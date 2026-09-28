import SwiftUI

struct PersonalListNavigationChrome: ViewModifier {
    let title: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                .prairieNavigationTitleDisplayMode(.large)
        } else {
            content
        }
    }
}
