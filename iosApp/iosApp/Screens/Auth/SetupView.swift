import SwiftUI

private enum SetupTextContentType {
    case username
    case emailAddress
}

private enum SetupKeyboardType {
    case `default`
    case emailAddress
}

/// First-time server setup: create the initial admin account.
struct SetupView: View {
    var router: AppRouter
    @State private var viewModel = SetupViewModel()

    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)

                    SiloWordmarkView(width: 132)

                    // Header
                    VStack(spacing: 4) {
                        Text("Create Admin Account")
                            .font(.continuumTitle)
                            .foregroundColor(.continuumOnSurface)

                        Text("Set up your Silo server")
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
                        Task { await viewModel.createAdmin(router: router) }
                    }
                    .buttonStyle(ContinuumPrimaryButtonStyle(isLoading: viewModel.isLoading))
                    .disabled(viewModel.isLoading)
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
        contentType: SetupTextContentType? = nil,
        keyboardType: SetupKeyboardType = .default
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
    private func systemTextContentType(_ contentType: SetupTextContentType?) -> UITextContentType? {
        switch contentType {
        case .username:
            .username
        case .emailAddress:
            .emailAddress
        case .none:
            nil
        }
    }

    private func systemKeyboardType(_ keyboardType: SetupKeyboardType) -> UIKeyboardType {
        switch keyboardType {
        case .default:
            .default
        case .emailAddress:
            .emailAddress
        }
    }
    #endif
}
