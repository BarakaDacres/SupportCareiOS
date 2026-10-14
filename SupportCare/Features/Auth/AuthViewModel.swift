import Foundation
import Observation
import SupportCareServices

@MainActor
@Observable
final class AuthViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp, forgot
        var id: String { rawValue }
        var title: String {
            switch self {
            case .signIn: "Sign in"
            case .signUp: "Create account"
            case .forgot: "Reset password"
            }
        }
    }

    var mode: Mode = .signIn
    var email = ""
    var password = ""
    var fullName = ""
    var isBusy = false
    var error: String?
    var message: String?

    let lastProvider = UserDefaults.standard.string(forKey: "last_auth_provider")

    private let auth: AuthServicing
    init(auth: AuthServicing) { self.auth = auth }

    var canSubmit: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        switch mode {
        case .forgot: return emailOK && !isBusy
        case .signIn: return emailOK && !password.isEmpty && !isBusy
        case .signUp: return emailOK && password.count >= 8 && !isBusy
        }
    }

    func submit() async {
        error = nil; message = nil
        isBusy = true
        defer { isBusy = false }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            switch mode {
            case .signIn:
                try await auth.signIn(email: email, password: password)
            case .signUp:
                let needsConfirm = try await auth.signUp(email: email, password: password, fullName: fullName.isEmpty ? nil : fullName)
                if needsConfirm { message = "Check your email to confirm your account."; mode = .signIn }
            case .forgot:
                try await auth.sendPasswordReset(email: email)
                message = "Password reset email sent. Open the link on this iPhone."
                mode = .signIn
            }
        } catch {
            self.error = Self.friendly(error)
        }
    }

    func apple(_ credential: AppleSignInCoordinator.Credential) async {
        await run { try await self.auth.signInWithApple(idToken: credential.idToken, nonce: credential.nonce, fullName: credential.fullName) }
    }

    func google() async {
        await run {
            guard let tokens = try await GoogleSignInCoordinator.signIn() else { return }
            try await self.auth.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
        }
    }

    func run(_ work: @escaping () async throws -> Void) async {
        error = nil
        isBusy = true
        defer { isBusy = false }
        do { try await work() } catch { self.error = Self.friendly(error) }
    }

    static func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") { return "Incorrect email or password." }
        if text.localizedCaseInsensitiveContains("already registered") { return "An account with this email already exists. Try signing in." }
        return text
    }
}
