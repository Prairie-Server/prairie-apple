import SwiftUI

/// Full-screen loading indicator.
struct LoadingView: View {
    var message: String? = nil
    var usesPageBackground = false

    var body: some View {
        ZStack {
            if usesPageBackground {
                PrairiePageBackdrop()
            } else {
                Color.prairieBackground.ignoresSafeArea()
            }

            VStack(spacing: 20) {
                PrairieWordmarkView(width: 132)

                ProgressView()
                    .tint(.prairieOnSurface)
                    .scaleEffect(1.2)

                if let message {
                    Text(message)
                        .font(.prairieCaption)
                        .foregroundColor(.prairieSecondaryText)
                }
            }
        }
    }
}
