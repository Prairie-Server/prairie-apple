import SwiftUI

struct PrairieWordmarkView: View {
    var width: CGFloat = 150
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image("PrairieWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: width)
                .accessibilityLabel("Prairie") // i18n-ignore: brand name

            if let subtitle {
                Text(subtitle)
                    .font(.prairieCaption)
                    .foregroundColor(.prairieSecondaryText)
                    .tracking(2)
            }
        }
    }
}
