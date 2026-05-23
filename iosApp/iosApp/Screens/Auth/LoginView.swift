import SwiftUI

/// Sign-in screen shown when the user has a configured server but no
/// active session. iOS-only now — tvOS uses `TVLoginView` which adds a
/// persistent QR pairing panel alongside the form.
struct LoginView: View {
    var router: AppRouter
    @State private var viewModel = LoginViewModel()
    @State private var showPassword: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username
        case password
    }

    var body: some View {
        ZStack {
            Color.continuumBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)

                    // Header
                    VStack(spacing: 4) {
                        Text("Welcome Back")
                            .font(.continuumTitle)
                            .foregroundColor(.continuumOnSurface)

                        Text("Sign in to continue")
                            .font(.continuumBody)
                            .foregroundColor(.continuumSecondaryText)
                    }

                    // Form fields
                    VStack(spacing: ContinuumTheme.padding) {
                        // Username
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username")
                                .font(.continuumCaption)
                                .foregroundColor(.continuumSecondaryText)

                            TextField("Username", text: $viewModel.username)
                                .textFieldStyle(ContinuumTextFieldStyle())
                                .focused($focusedField, equals: .username)
                                .textContentType(.username)
                                #if !os(macOS)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                #endif
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.continuumCaption)
                                .foregroundColor(.continuumSecondaryText)

                            HStack(spacing: 0) {
                                Group {
                                    if showPassword {
                                        TextField("Password", text: $viewModel.password)
                                    } else {
                                        SecureField("Password", text: $viewModel.password)
                                    }
                                }
                                .focused($focusedField, equals: .password)
                                .textContentType(.password)
                                #if !os(macOS)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                #endif

                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.continuumSecondaryText)
                                }
                                .padding(.trailing, 4)
                            }
                            .font(.continuumBody)
                            // tvOS paints a white focus platter under the
                            // text field; flip text color to dark on focus
                            // so dots / typed text remain legible on the
                            // inverted surface. Matches
                            // `ContinuumTextFieldBody` above.
                            .foregroundColor(passwordTextColor)
                            .padding(.horizontal, ContinuumTheme.padding)
                            .padding(.vertical, 14)
                            .continuumInputChrome(isFocused: focusedField == .password)
                            .tint(focusedField == .password ? .continuumBackground : .continuumPrimary)
                        }
                    }

                    // Error
                    if let error = viewModel.error {
                        Text(error)
                            .font(.continuumCaption)
                            .foregroundColor(.continuumError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Sign In button
                    Button("Sign In") {
                        Task { await viewModel.login(router: router) }
                    }
                    .buttonStyle(ContinuumPrimaryButtonStyle(isLoading: viewModel.isLoading))
                    .disabled(viewModel.isLoading)

                    // Signup link
                    if viewModel.signupEnabled {
                        Button("Create Account") {
                            router.navigate(to: .signup)
                        }
                        .buttonStyle(ContinuumTextButtonStyle())
                    }

                    // Change server
                    Button("Change Server") {
                        router.resetToServerSetup()
                    }
                    .buttonStyle(ContinuumTextButtonStyle())
                    .padding(.top, 8)
                }
                .padding(.horizontal, ContinuumTheme.largePadding)
                .continuumFormWidth()
            }
        }
        .navigationBarBackButtonHidden()
        .task {
            await viewModel.checkSignupStatus()
        }
    }

    private var passwordTextColor: Color {
        Color.continuumOnSurface
    }
}
