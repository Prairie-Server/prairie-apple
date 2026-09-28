import SwiftUI

/// Displays a placeholder when a list or grid has no content.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.prairieOnSurface.opacity(0.3))

            Text(title)
                .font(.prairieSubheadline)
                .foregroundColor(.prairieOnSurface)

            if let subtitle {
                Text(subtitle)
                    .font(.prairieCaption)
                    .foregroundColor(.prairieSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PrairieTheme.largePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
