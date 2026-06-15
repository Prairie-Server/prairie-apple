import SwiftUI

#if !os(tvOS)
/// Account registration (Aurora). Shown when signup is enabled on the server.
struct SignupView: View {
    var router: AppRouter
    @State private var viewModel = SignupViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case username, email, password, confirm, invite }

    var body: some View {
        AuroraScreen(variant: .signIn, scrim: .soft) {
            SiloWordmarkView(width: 132)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)

            VStack(spacing: 12) {
                AuroraEyebrow(text: "Create account", centered: true)
                Text("Create your account")
                    .font(.continuumTitle)
                    .foregroundStyle(Color.auroraInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 16) {
                AuroraTextField(
                    label: "Username", text: $viewModel.username, placeholder: "yourname",
                    focus: $focusedField, equals: .username,
                    contentType: .username, onSubmit: { focusedField = .email }
                )
                AuroraTextField(
                    label: "Email", text: $viewModel.email, placeholder: "you@example.com",
                    focus: $focusedField, equals: .email,
                    contentType: .email, keyboard: .email, onSubmit: { focusedField = .password }
                )
                AuroraTextField(
                    label: "Password", text: $viewModel.password, placeholder: "••••••",
                    focus: $focusedField, equals: .password,
                    isSecure: true, showsRevealToggle: true,
                    contentType: .password, onSubmit: { focusedField = .confirm }
                )
                AuroraTextField(
                    label: "Confirm password", text: $viewModel.confirmPassword, placeholder: "••••••",
                    focus: $focusedField, equals: .confirm,
                    isSecure: true, contentType: .password, onSubmit: { focusedField = .invite }
                )
                AuroraTextField(
                    label: "Invite code", text: $viewModel.inviteCode, placeholder: "ABCD-1234",
                    focus: $focusedField, equals: .invite,
                    contentType: .oneTimeCode, submitLabel: .go, onSubmit: { createAccount() }
                )

                if let error = viewModel.error {
                    AuroraErrorLabel(error)
                }

                Button {
                    createAccount()
                } label: {
                    Text(viewModel.isLoading ? "Creating…" : "Create account")
                }
                .buttonStyle(AuroraPrimaryButtonStyle(isLoading: viewModel.isLoading))
                .disabled(viewModel.isLoading)
                .padding(.top, 4)

                Button("Back to sign in") { router.goBack() }
                    .buttonStyle(AuroraGhostButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(22)
            .auroraGlass(cornerRadius: 24, emphasized: true)
            .animation(.easeInOut(duration: 0.2), value: viewModel.error)
        }
        .navigationBarBackButtonHidden()
    }

    private func createAccount() {
        guard !viewModel.isLoading else { return }
        Task { await viewModel.signup(router: router) }
    }
}
#endif
