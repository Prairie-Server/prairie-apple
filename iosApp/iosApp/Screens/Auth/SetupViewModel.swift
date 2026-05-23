import Foundation

@Observable
class SetupViewModel {
    var username: String = ""
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var isLoading: Bool = false
    var error: String?

    private let auth = AuthService.shared

    /// Create the initial admin account during first-time server setup.
    func createAdmin(router: AppRouter) async {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Please enter a username."
            return
        }
        guard password.count >= 8 else {
            error = "Password must be at least 8 characters."
            return
        }
        guard password == confirmPassword else {
            error = "Passwords do not match."
            return
        }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Please enter an email address."
            return
        }
        guard email.contains("@") else {
            error = "Please enter a valid email address."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await auth.setupAdmin(
                username: username,
                email: email,
                password: password
            )
            await StartupContentPrefetcher.prefetchProfiles()
            router.showProfileSelection()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
