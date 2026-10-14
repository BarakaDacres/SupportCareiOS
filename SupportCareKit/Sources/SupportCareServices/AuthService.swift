import Foundation
import Supabase
import SupportCareCore

public enum AuthEvent: Sendable, Equatable {
    case signedIn(userId: UUID, email: String?)
    case signedOut
    /// The user opened a password-reset link; show the new-password screen.
    case passwordRecovery(userId: UUID)
}

public enum DeepLinkResult: Sendable, Equatable {
    case notAuth, signedIn, passwordRecovery
    case failed(String)
}

public protocol AuthServicing: Sendable {
    var events: AsyncStream<AuthEvent> { get }
    func signIn(email: String, password: String) async throws
    /// Returns true if email confirmation is required before a session exists.
    func signUp(email: String, password: String, fullName: String?) async throws -> Bool
    func sendPasswordReset(email: String) async throws
    func updatePassword(_ newPassword: String) async throws
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws
    func signInWithGoogle(idToken: String, accessToken: String?) async throws
    /// Handles supportcare:// deep links (PKCE code exchange).
    func handle(url: URL) async -> DeepLinkResult
    func signOut() async throws
}

public final class SupabaseAuthService: AuthServicing {
    private let client: SupabaseClient
    private let config: SupabaseConfig

    public init(client: SupabaseClient, config: SupabaseConfig) {
        self.client = client
        self.config = config
    }

    public var events: AsyncStream<AuthEvent> {
        let auth = client.auth
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in auth.authStateChanges {
                    switch event {
                    case .passwordRecovery:
                        if let s = session { continuation.yield(.passwordRecovery(userId: s.user.id)) }
                    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                        if let s = session, !s.isExpired {
                            continuation.yield(.signedIn(userId: s.user.id, email: s.user.email))
                        } else if event == .initialSession {
                            continuation.yield(.signedOut)
                        }
                    case .signedOut, .userDeleted:
                        continuation.yield(.signedOut)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
        UserDefaults.standard.set("email", forKey: "last_auth_provider")
    }

    public func signUp(email: String, password: String, fullName: String?) async throws -> Bool {
        var data: [String: AnyJSON]?
        if let fullName, !fullName.isEmpty { data = ["full_name": .string(fullName)] }
        let response = try await client.auth.signUp(email: email, password: password, data: data, redirectTo: config.authCallbackURL)
        return response.session == nil
    }

    public func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: config.passwordResetURL)
    }

    public func updatePassword(_ newPassword: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: newPassword))
    }

    public func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        UserDefaults.standard.set("apple", forKey: "last_auth_provider")
        // Apple only returns the name on first authorisation; persist it to profile metadata.
        if let fullName, !fullName.isEmpty {
            _ = try? await client.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
        }
    }

    public func signInWithGoogle(idToken: String, accessToken: String?) async throws {
        try await client.auth.signInWithIdToken(credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken))
        UserDefaults.standard.set("google", forKey: "last_auth_provider")
    }

    public func handle(url: URL) async -> DeepLinkResult {
        guard url.scheme == config.redirectScheme else { return .notAuth }
        do {
            _ = try await client.auth.session(from: url)
            // With PKCE, Supabase doesn't emit PASSWORD_RECOVERY, so the link's host decides.
            return url.host == "reset-password" ? .passwordRecovery : .signedIn
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func signOut() async throws {
        try await client.auth.signOut()
    }
}

/// Generates the nonce pair Sign in with Apple needs: the raw value goes to Supabase,
/// and the SHA-256 hash goes to Apple.
public enum Nonce {
    public static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset[Int(rng.next(upperBound: UInt32(charset.count)))] })
    }
}
