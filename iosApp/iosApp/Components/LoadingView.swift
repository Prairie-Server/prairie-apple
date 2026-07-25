import SwiftUI

/// Full-screen loading indicator.
struct LoadingView: View {
    var message: String? = nil

    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                PrairieWordmarkView(width: 132)

                ProgressView()
                    .tint(.continuumOnSurface)
                    .scaleEffect(1.2)

                if let message {
                    Text(message)
                        .font(.continuumCaption)
                        .foregroundColor(.continuumSecondaryText)
                }
            }
        }
    }
}
