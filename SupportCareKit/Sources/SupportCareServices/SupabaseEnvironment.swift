import Foundation
import Supabase

/// Supabase connection settings. On iOS these come from Info.plist keys
/// `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, which `Config.xcconfig` (gitignored) fills in.
public struct SupabaseConfig: Sendable {
    public var url: URL
    public var publishableKey: String
    /// Custom URL scheme used for auth redirects (password reset, email confirmation).
    public var redirectScheme: String

    public init(url: URL, publishableKey: String, redirectScheme: String = "supportcare") {
        self.url = url
        self.publishableKey = publishableKey
        self.redirectScheme = redirectScheme
    }

    public enum ConfigError: Error, LocalizedError {
        case missing(String)
        public var errorDescription: String? {
            switch self {
            case .missing(let key): "Missing \(key). Copy Config.example.xcconfig to Config.xcconfig and fill it in."
            }
        }
    }

    public static func fromBundle(_ bundle: Bundle = .main) throws -> SupabaseConfig {
        func value(_ key: String) -> String? {
            let v = (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
            return (v?.isEmpty == false && v?.hasPrefix("$(") == false) ? v : nil
        }
        guard let urlString = value("SUPABASE_URL"), let url = URL(string: urlString) else { throw ConfigError.missing("SUPABASE_URL") }
        guard let key = value("SUPABASE_PUBLISHABLE_KEY") else { throw ConfigError.missing("SUPABASE_PUBLISHABLE_KEY") }
        return SupabaseConfig(url: url, publishableKey: key, redirectScheme: value("AUTH_REDIRECT_SCHEME") ?? "supportcare")
    }

    /// supportcare://auth-callback is used for email confirmation.
    public var authCallbackURL: URL { URL(string: "\(redirectScheme)://auth-callback")! }
    /// supportcare://reset-password: opening it shows the new-password screen.
    public var passwordResetURL: URL { URL(string: "\(redirectScheme)://reset-password")! }
}

public enum SupabaseFactory {
    public static func makeClient(_ config: SupabaseConfig) -> SupabaseClient {
        #if canImport(Security) && !os(Linux)
        let auth = SupabaseClientOptions.AuthOptions(
            redirectToURL: config.authCallbackURL,
            flowType: .pkce,
            emitLocalSessionAsInitialSession: true
        )
        #else
        let auth = SupabaseClientOptions.AuthOptions(
            storage: InMemoryAuthStorage(),
            redirectToURL: config.authCallbackURL,
            flowType: .pkce,
            emitLocalSessionAsInitialSession: true
        )
        #endif
        return SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(auth: auth)
        )
    }
}

/// Used only off-Apple (Linux CI compile checks); iOS uses the Keychain-backed default.
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}
