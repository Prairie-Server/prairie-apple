#if os(iOS)
import SwiftUI

struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.prairieSecondaryText)
                .accessibilityHidden(true)

            TextField("Search settings", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.prairieOnSurface)

            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.prairieSecondaryText)
                .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 48)
        .background(Color.prairieSurfaceElevated.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(Color.prairieOutline, lineWidth: 1)
        }
    }
}
#endif
