#if os(tvOS)
import SwiftUI

/// The "Set up with iPhone" panel shown on the tvOS onboarding screen.
/// Advertises on the LAN and, once a phone connects, shows the match code to
/// confirm. Falls through to the host screen's QR / manual entry otherwise.
struct TVPairingReceiverView: View {
    var router: AppRouter

    @State private var advertiser = TVPairingAdvertiser()
    @State private var coordinator: ReceiverPairingCoordinator?

    var body: some View {
        VStack(spacing: 28) {
            switch coordinator?.state ?? .idle {
            case .idle:
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 64, weight: .semibold))
                Text("Set up with iPhone")
                    .font(.system(size: 40, weight: .bold))
                Text("Open Silo on your iPhone on the same Wi-Fi. It will offer to set up this Apple TV.")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 720)
            case let .awaitingApproval(serverName, matchCode):
                Text("Confirm on your iPhone")
                    .font(.system(size: 40, weight: .bold))
                Text(matchCode)
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .textCase(.uppercase)
                Text("Make sure your iPhone shows this same code for \(serverName).")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 720)
            case let .signedIn(count):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text(count == 1 ? "Signed in" : "Signed in to \(count) servers")
                    .font(.system(size: 40, weight: .bold))
            case let .failed(name):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.yellow)
                Text("Couldn’t set up \(name). Try again, or use the QR code.")
                    .font(.system(size: 24))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 720)
            }
        }
        .task { start() }
        .onDisappear { advertiser.stop() }
    }

    private func start() {
        let coordinator = ReceiverPairingCoordinator { router.showProfileSelection() }
        self.coordinator = coordinator
        advertiser.start { session, stream in
            Task {
                await coordinator.run(session: session, stream: stream)
                advertiser.release()
            }
        }
    }
}
#endif
