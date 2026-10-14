import AuthenticationServices
import CryptoKit
import GoogleSignIn
import SwiftUI
import UIKit

/// Native Sign in with Apple: SHA-256(nonce) goes to Apple, the raw nonce goes to Supabase `signInWithIdToken`.
@MainActor
final class AppleSignInCoordinator {
    private(set) var rawNonce = ""

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        rawNonce = randomNonce()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)
    }

    struct Credential { let idToken: String; let nonce: String; let fullName: String? }

    func credential(from result: Result<ASAuthorization, Error>) throws -> Credential? {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return nil }
            throw error
        case .success(let auth):
            guard let apple = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw SignInError.missingToken
            }
            let name = apple.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
            return Credential(idToken: token, nonce: rawNonce, fullName: name?.isEmpty == true ? nil : name)
        }
    }

    private func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum SignInError: LocalizedError {
    case missingToken, notConfigured, noWindow
    var errorDescription: String? {
        switch self {
        case .missingToken: "The sign-in provider didn't return an identity token."
        case .notConfigured: "Google Sign-In isn't configured. Add GOOGLE_IOS_CLIENT_ID to Config.xcconfig."
        case .noWindow: "Couldn't find a window to present sign-in from."
        }
    }
}

/// Native Google Sign-In (GoogleSignIn-iOS SDK) → Supabase `signInWithIdToken(provider: .google)`.
@MainActor
enum GoogleSignInCoordinator {
    static var isConfigured: Bool {
        let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        return !id.isEmpty && !id.hasPrefix("$(")
    }

    static func signIn() async throws -> (idToken: String, accessToken: String)? {
        guard isConfigured else { throw SignInError.notConfigured }
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { throw SignInError.noWindow }
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw SignInError.missingToken }
            return (idToken, result.user.accessToken.tokenString)
        } catch let error as GIDSignInError where error.code == .canceled {
            return nil
        }
    }
}

/// Google-branded button styled for Liquid Glass.
struct GoogleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("G")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Sign in with Google").font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }
}
