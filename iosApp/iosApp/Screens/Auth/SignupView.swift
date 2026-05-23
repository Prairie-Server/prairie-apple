import SwiftUI

private enum ContinuumTextContentType {
    case username
    case emailAddress
    case oneTimeCode
    case password
}

private enum ContinuumKeyboardType {
    case `default`
    case emailAddress
}

/// Account registration screen (shown when signup is enabled on the server).
struct SignupView: View {
    var router: AppRouter
    @State private var viewModel = SignupViewModel()

    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)

                    // Header
                    VStack(spacing: 4) {
                        Text("Create Account")
                            .font(.continuumTitle)
                            .foregroundColor(.continuumOnSurface)

                        Text("Join the server")
                            .font(.continuumBody)
                            .foregroundColor(.continuumSecondaryText)
                    }

                    // Form
                    VStack(spacing: ContinuumTheme.padding) {
                        formField("Username", text: $viewModel.username, contentType: .username)
                        formField(
                            "Email",
                            text: $viewModel.email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress
                        )
                        secureField("Password", text: $viewModel.password)
                        secureField("Confirm Password", text: $viewModel.confirmPassword)
                        formField(
                            "Invite Code",
                            text: $viewModel.inviteCode,
                            contentType: .oneTimeCode
                        )
                    }

                    // Error
                    if let error = viewModel.error {
                        Text(error)
                            .font(.continuumCaption)
                            .foregroundColor(.continuumError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Submit
                    Button("Create Account") {
                        Task { await viewModel.signup(router: router) }
                    }
                    .buttonStyle(ContinuumPrimaryButtonStyle(isLoading: viewModel.isLoading))
                    .disabled(viewModel.isLoading)

                    // Back to login
                    Button("Already have an account? Sign In") {
                        router.goBack()
                    }
                    .buttonStyle(ContinuumTextButtonStyle())
                }
                .padding(.horizontal, ContinuumTheme.largePadding)
                .continuumFormWidth()
            }
        }
        .navigationBarBackButtonHidden()
    }

    // MARK: - Helpers

    private func formField(
        _ label: String,
        text: Binding<String>,
        contentType: ContinuumTextContentType? = nil,
        keyboardType: ContinuumKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.continuumCaption)
                .foregroundColor(.continuumSecondaryText)

            TextField(label, text: text)
                .textFieldStyle(ContinuumTextFieldStyle())
                #if !os(macOS)
                .textContentType(systemTextContentType(contentType))
                .keyboardType(systemKeyboardType(keyboardType))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
        }
    }

    private func secureField(
        _ label: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.continuumCaption)
                .foregroundColor(.continuumSecondaryText)

            SecureField(label, text: text)
                .textFieldStyle(ContinuumTextFieldStyle())
                #if !os(macOS)
                .textContentType(.password)
                #endif
        }
    }

    #if !os(macOS)
    private func systemTextContentType(_ contentType: ContinuumTextContentType?) -> UITextContentType? {
        switch contentType {
        case .username:
            .username
        case .emailAddress:
            .emailAddress
        case .oneTimeCode:
            .oneTimeCode
        case .password:
            .password
        case .none:
            nil
        }
    }

    private func systemKeyboardType(_ keyboardType: ContinuumKeyboardType) -> UIKeyboardType {
        switch keyboardType {
        case .default:
            .default
        case .emailAddress:
            .emailAddress
        }
    }
    #endif
}
