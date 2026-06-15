import SwiftUI

#if !os(tvOS)
/// Shown when the chosen server has no account yet (`/api/v1/auth/setup`
/// reports `needsSetup`). iOS no longer creates the admin account in-app —
/// that happens in the server's web UI — so we point the user there and offer
/// a retry that re-probes the server.
struct ServerNeedsSetupView: View {
    var router: AppRouter
    @State private var isChecking = false
    @State private var error: String?

    var body: some View {
        AuroraScreen(variant: .server, scrim: .soft) {
            SiloWordmarkView(width: 132)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 26)

            AuroraEyebrow(text: "Setup needed", centered: true)
                .padding(.bottom, 18)

            ZStack {
                Circle().fill(Color.auroraAccent.opacity(0.14))
                Circle().stroke(Color.auroraAccent.opacity(0.34), lineWidth: 1)
                Image(systemName: "gearshape.2")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.auroraAccent)
            }
            .frame(width: 78, height: 78)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)

            VStack(spacing: 12) {
                Text("Finish setup in your browser")
                    .font(.continuumTitle)
                    .foregroundStyle(Color.auroraInk)
                    .multilineTextAlignment(.center)
                Text("This server doesn't have an account yet. Open it in a browser to create the first one, then come back here to sign in.")
                    .font(.continuumBody)
                    .foregroundStyle(Color.auroraInkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)

            VStack(spacing: 16) {
                if let host {
                    HStack(spacing: 10) {
                        Text(host)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.auroraInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        #if os(iOS)
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(Color.auroraInkTertiary)
                        #endif
                    }
                    .padding(.horizontal, 16)
                    .frame(height: AuroraControl.height)
                    .background(
                        RoundedRectangle(cornerRadius: AuroraControl.corner, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraControl.corner, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1.5)
                    )
                    #if os(iOS)
                    .onTapGesture { copyURL() }
                    #endif
                }

                if let error {
                    AuroraErrorLabel(error)
                }

                Button {
                    retry()
                } label: {
                    Text(isChecking ? "Checking…" : "I've done that — retry")
                }
                .buttonStyle(AuroraPrimaryButtonStyle(isLoading: isChecking))
                .disabled(isChecking)

                Button("Change server") { router.resetToServerSetup() }
                    .buttonStyle(AuroraGhostButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(22)
            .auroraGlass(cornerRadius: 24, emphasized: true)
            .animation(.easeInOut(duration: 0.2), value: error)
        }
        .navigationBarBackButtonHidden()
    }

    private var host: String? {
        let url = AuthService.shared.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        if let parsed = URL(string: url), let host = parsed.host, !host.isEmpty { return host }
        return url.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    private func copyURL() {
        #if os(iOS)
        UIPasteboard.general.string = AuthService.shared.serverUrl
        #endif
    }

    /// Re-probe the current server. If it's now set up, pop back to the login
    /// screen (this view sits on top of `LoginView` in the `.needsLogin`
    /// stack). Otherwise surface a gentle nudge.
    private func retry() {
        guard !isChecking else { return }
        isChecking = true
        error = nil
        Task {
            do {
                let status = try await AuthService.shared.checkServer(url: AuthService.shared.serverUrl)
                await MainActor.run {
                    isChecking = false
                    if status.needsSetup {
                        error = "This server still needs to be set up in a browser."
                    } else {
                        router.goBack()
                    }
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                    self.error = "Couldn't reach the server. Check it's running and try again."
                }
            }
        }
    }
}
#endif
