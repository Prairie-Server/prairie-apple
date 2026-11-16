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

            TextField(text: $text, prompt: Text(.settingsSearchPlaceholder)) {
                Text(.settingsSearchPlaceholder)
            }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.prairieOnSurface)
                .accessibilityLabel(Text(.settingsSearchFieldLabel))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Label(.settingsSearchClear, systemImage: "xmark.circle.fill")
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
