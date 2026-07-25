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
                .accessibilityLabel("Prairie")

            if let subtitle {
                Text(subtitle)
                    .font(.continuumCaption)
                    .foregroundColor(.continuumSecondaryText)
                    .tracking(2)
            }
        }
    }
}
