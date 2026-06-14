#if os(tvOS)
import SwiftUI

/// The pairing panel rendered *in place* inside `TVServerSetupView` once a phone
/// connects — it replaces the two-card "Add your server" layout while a session
/// is live, on the same Aurora backdrop (no cover, so nothing bleeds through).
/// `TVServerSetupView` owns the advertiser + coordinator lifecycle; this view is
/// pure presentation of `coordinator.state` plus a focusable escape hatch.
struct TVPairingReceiverView: View {
    var coordinator: ReceiverPairingCoordinator
    var router: AppRouter

    /// Dwell on the success screen before advancing, so it isn't a flash.
    private static let successDwell: Duration = .seconds(1.8)

    @FocusState private var focused: Control?
    private enum Control: Hashable { case primary }

    var body: some View {
        VStack(spacing: 28) {
            switch coordinator.state {
            case .idle:
                // Host renders the two-card layout for idle; nothing to show here.
                EmptyView()
            case .linked:
                linked
            case let .awaitingApproval(serverName, matchCode):
                awaitingApproval(serverName: serverName, matchCode: matchCode)
            case let .signedIn(count):
                signedIn(count: count)
            case let .completed(serverNames):
                completed(serverNames: serverNames)
            case let .failed(name):
                failed(name: name)
            }
        }
        .frame(maxWidth: 880)
        .multilineTextAlignment(.center)
    }

    // MARK: - Linked (phone connected, picking servers on its end)

    private var linked: some View {
        VStack(spacing: 26) {
            AuroraEyebrow(text: "Step 01 — Connect", centered: true)
            Text("iPhone connected")
                .font(.auroraSerif(52, .semibold))
                .foregroundStyle(Color.auroraInk)
            WaitingDots()
            Text("Choose which servers to set up on your iPhone — they’ll appear here in a moment.")
                .font(.system(size: 24))
                .foregroundStyle(Color.auroraInkSecondary)
                .frame(maxWidth: 720)
            cancelButton(title: "Cancel")
                .padding(.top, 8)
        }
    }

    // MARK: - Awaiting approval (match code)

    private func awaitingApproval(serverName: String, matchCode: String) -> some View {
        VStack(spacing: 24) {
            AuroraEyebrow(text: "Almost there", centered: true)
            Text("Confirm on your iPhone")
                .font(.auroraSerif(52, .semibold))
                .foregroundStyle(Color.auroraInk)

            matchCodeCard(matchCode)

            VStack(spacing: 10) {
                Text("SETTING UP")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.auroraInkTertiary)
                Text(serverName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.auroraInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 12) {
                WaitingDots(compact: true)
                Text("Waiting for approval on your iPhone — make sure it shows this same code.")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.auroraInkSecondary)
            }
            .frame(maxWidth: 720)

            cancelButton(title: "Cancel")
                .padding(.top, 6)
        }
    }

    private func matchCodeCard(_ matchCode: String) -> some View {
        Text(matchCode)
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(Color.auroraInk)
            .padding(.horizontal, 56)
            .padding(.vertical, 28)
            .auroraGlass(cornerRadius: 24, emphasized: true)
            .fixedSize()
    }

    // MARK: - Signed in (interim, per server during multi-server)

    private func signedIn(count: Int) -> some View {
        VStack(spacing: 20) {
            successMark
            Text(count <= 1 ? "Signed in" : "Signed in to \(count) servers")
                .font(.auroraSerif(46, .semibold))
                .foregroundStyle(Color.auroraInk)
            HStack(spacing: 12) {
                WaitingDots(compact: true)
                Text("Finishing up on your iPhone…")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.auroraInkSecondary)
            }
            cancelButton(title: "Cancel")
                .padding(.top, 4)
        }
    }

    // MARK: - Completed (terminal success → advance to profiles)

    private func completed(serverNames: [String]) -> some View {
        VStack(spacing: 22) {
            AuroraEyebrow(text: "All set", centered: true)
            successMark
            Text("You’re all set")
                .font(.auroraSerif(52, .semibold))
                .foregroundStyle(Color.auroraInk)
            Text(completedSummary(serverNames))
                .font(.system(size: 24))
                .foregroundStyle(Color.auroraInkSecondary)
                .frame(maxWidth: 720)

            Button { advance() } label: { Text("Continue") }
                .buttonStyle(AuroraPrimaryButtonStyle())
                .focused($focused, equals: .primary)
                .frame(width: 360)
                .padding(.top, 8)
        }
        .task {
            // Auto-advance after a short dwell; the button skips the wait.
            try? await Task.sleep(for: Self.successDwell)
            advance()
        }
        .defaultFocus($focused, .primary)
    }

    private func completedSummary(_ names: [String]) -> String {
        switch names.count {
        case 0: return "Taking you to your profiles…"
        case 1: return "Signed in to \(names[0]). Taking you to your profiles…"
        default: return "Signed in to \(names.joined(separator: ", ")). Taking you to your profiles…"
        }
    }

    // MARK: - Failed (actionable retry)

    private func failed(name: String) -> some View {
        VStack(spacing: 22) {
            AuroraEyebrow(text: "Step 01 — Connect", centered: true)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.auroraAccent)
            Text("Setup didn’t finish")
                .font(.auroraSerif(52, .semibold))
                .foregroundStyle(Color.auroraInk)
            Text("Something went wrong setting up \(name). Try again from your iPhone, or set up your server manually.")
                .font(.system(size: 24))
                .foregroundStyle(Color.auroraInkSecondary)
                .frame(maxWidth: 720)

            Button { cancel() } label: { Text("Try again") }
                .buttonStyle(AuroraPrimaryButtonStyle())
                .focused($focused, equals: .primary)
                .frame(width: 360)
                .padding(.top, 8)
        }
        .defaultFocus($focused, .primary)
    }

    // MARK: - Shared pieces

    private var successMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(Color.green)
            .shadow(color: Color.green.opacity(0.4), radius: 24)
    }

    private func cancelButton(title: String) -> some View {
        Button { cancel() } label: { Text(title) }
            .buttonStyle(AuroraGhostButtonStyle())
            .focused($focused, equals: .primary)
    }

    // MARK: - Actions

    /// Tear down the session and return the host to its idle two-card layout
    /// (the advertiser keeps listening, so a fresh phone attempt just works).
    private func cancel() {
        Task { await coordinator.cancel() }
    }

    private func advance() {
        router.showProfileSelection()
    }
}

// MARK: - Waiting indicator

/// Three softly pulsing dots for "waiting on your phone" states.
private struct WaitingDots: View {
    var compact: Bool = false
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dot: CGFloat { compact ? 8 : 12 }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.auroraAccent)
                    .frame(width: dot, height: dot)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                        value: animating)
            }
        }
        .onAppear { animating = true }
    }
}
#endif
