#if os(iOS)
import SwiftUI

/// Capsule search field in the system search-bar style, placed in the
/// Settings list between the profile and the first section.
struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.prairieSecondaryText)
                .accessibilityHidden(true)

            TextField("Search", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.prairieOnSurface)
                .accessibilityLabel("Search settings")

            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Color.prairieSecondaryText)
                .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.prairieGroupedCell, in: Capsule())
    }
}
#endif
