import Foundation

@Observable
class LoginViewModel {
    var username: String = ""
    var password: String = ""
    var isLoading: Bool = false
    var error: String?
    var signupEnabled: Bool = false

    private let auth = AuthService.shared

    /// Check whether signup is available on this server.
    func checkSignupStatus() async {
        do {
            let status: SignupStatus = try await ContinuumAPI.shared.get("/api/v1/auth/signup")
            signupEnabled = status.enabled
        } catch {
            // Non-critical; just hide the signup link.
            signupEnabled = false
        }
    }

    /// Authenticate with username and password.
    func login(router: AppRouter) async {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Please enter your username."
            return
        }
        guard !password.isEmpty else {
            error = "Please enter your password."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await auth.login(username: username, password: password)
            await StartupContentPrefetcher.prefetchProfiles()
            router.showProfileSelection()
        } catch let loginError {
            self.error = loginError.localizedDescription
        }
    }
}
