import SwiftUI

#if !os(tvOS)
/// Password-first sign-in (Aurora). iOS/macOS only — tvOS uses `TVLoginView`,
/// which leads with QR device-login. Here the phone *is* the device, so we go
/// straight to username/password over the plum backdrop.
struct LoginView: View {
    var router: AppRouter
    @State private var viewModel = LoginViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case username, password }

    var body: some View {
        AuroraScreen(variant: .signIn, scrim: .soft) {
            SiloWordmarkView(width: 132)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)

            VStack(spacing: 12) {
                AuroraEyebrow(text: "Step 02 — Sign in", centered: true)
                Text("Welcome back")
                    .font(.continuumTitle)
                    .foregroundStyle(Color.auroraInk)
                if let host = hostLabel {
                    Text(host)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.auroraInkTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 18) {
                AuroraTextField(
                    label: "Username",
                    text: $viewModel.username,
                    placeholder: "yourname",
                    focus: $focusedField,
                    equals: .username,
                    contentType: .username,
                    submitLabel: .next,
                    onSubmit: { focusedField = .password }
                )

                AuroraTextField(
                    label: "Password",
                    text: $viewModel.password,
                    placeholder: "••••••",
                    focus: $focusedField,
                    equals: .password,
                    isSecure: true,
                    showsRevealToggle: true,
                    contentType: .password,
                    submitLabel: .go,
                    onSubmit: { signIn() }
                )

                if let error = viewModel.error {
                    AuroraErrorLabel(error)
                }

                Button {
                    signIn()
                } label: {
                    Text(viewModel.isLoading ? "Signing in…" : "Sign in")
                }
                .buttonStyle(AuroraPrimaryButtonStyle(isLoading: viewModel.isLoading))
                .disabled(viewModel.isLoading)
                .padding(.top, 4)

                HStack(spacing: 14) {
                    if viewModel.signupEnabled {
                        Button("Create account") { router.navigate(to: .signup) }
                            .buttonStyle(AuroraGhostButtonStyle())
                    }
                    Button("Change server") { router.resetToServerSetup() }
                        .buttonStyle(AuroraGhostButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isLoading)
                .padding(.top, 4)
            }
            .padding(22)
            .auroraGlass(cornerRadius: 24, emphasized: true)
            .animation(.easeInOut(duration: 0.2), value: viewModel.error)
        }
        .navigationBarBackButtonHidden()
        .task { await viewModel.checkSignupStatus() }
    }

    private func signIn() {
        guard !viewModel.isLoading else { return }
        Task { await viewModel.login(router: router) }
    }

    /// Host pulled out of the active server URL so the user sees which server
    /// they're signing into. Mirrors `TVLoginView.hostLabel`.
    private var hostLabel: String? {
        let url = AuthService.shared.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        if let parsed = URL(string: url), let host = parsed.host, !host.isEmpty {
            return host
        }
        return url.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }
}
#endif
