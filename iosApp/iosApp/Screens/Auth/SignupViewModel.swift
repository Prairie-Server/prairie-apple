import Foundation

@Observable
class SignupViewModel {
    var username: String = ""
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var inviteCode: String = ""
    var isLoading: Bool = false
    var error: String?

    private let auth = AuthService.shared

    /// Register a new user account.
    func signup(router: AppRouter) async {
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
        guard !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Please enter an invite code."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await auth.signup(
                username: username,
                email: email,
                password: password,
                inviteCode: inviteCode
            )
            await StartupContentPrefetcher.prefetchProfiles()
            router.showProfileSelection()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
