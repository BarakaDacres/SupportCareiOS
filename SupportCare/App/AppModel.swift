import Foundation
import Observation
import SupportCareCore
import SupportCareServices

/// App-wide session state machine:
/// launching → signedOut ⇄ (passwordRecovery) → onboarding → ready
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case misconfigured(String)
        case signedOut
        case passwordRecovery
        case onboarding
        case ready
    }

    private(set) var phase: Phase = .launching
    private(set) var userId: UUID?
    private(set) var email: String?
    var authNotice: String?

    let auth: AuthServicing
    let repository: DataRepository
    let config: SupabaseConfig?
    private(set) var store: DataStore?
    private var started = false
    private var recoveryPending = false

    init(auth: AuthServicing, repository: DataRepository, config: SupabaseConfig?, configError: String? = nil) {
        self.auth = auth
        self.repository = repository
        self.config = config
        if let configError { phase = .misconfigured(configError) }
    }

    static func live() -> AppModel {
        do {
            let config = try SupabaseConfig.fromBundle()
            let client = SupabaseFactory.makeClient(config)
            return AppModel(auth: SupabaseAuthService(client: client, config: config),
                            repository: SupabaseRepository(client: client), config: config)
        } catch {
            return demo(configError: error.localizedDescription)
        }
    }

    /// Offline demo with sample data (used for previews and when Supabase isn't configured).
    static func demo(configError: String? = nil) -> AppModel {
        AppModel(auth: DemoAuthService(), repository: InMemoryRepository(), config: nil, configError: configError)
    }

    var isDemo: Bool { config == nil }

    func start() async {
        guard !started else { return }
        started = true
        for await event in auth.events {
            await apply(event)
        }
    }

    func enterDemoMode() {
        Task { try? await auth.signIn(email: "demo@supportcare.app", password: "demo") }
    }

    private func apply(_ event: AuthEvent) async {
        switch event {
        case .signedOut:
            userId = nil; email = nil; store = nil
            phase = .signedOut
        case .passwordRecovery(let uid):
            userId = uid
            phase = .passwordRecovery
        case .signedIn(let uid, let mail):
            email = mail
            if recoveryPending { userId = uid; phase = .passwordRecovery; return }
            guard userId != uid || store == nil else { return } // token refresh
            userId = uid
            if isDemo, let demo = repository as? InMemoryRepository { await demo.seedIfEmpty(userId: uid) }
            let store = DataStore(userId: uid, repository: repository)
            self.store = store
            await store.loadAll()
            phase = (store.settings?.hasCompletedOnboarding ?? false) ? .ready : .onboarding
            NotificationScheduler.shared.refresh(store: store)
        }
    }

    func handle(url: URL) async {
        // Set before the exchange, because signedIn fires during it.
        if url.host == "reset-password" { recoveryPending = true }
        let result = await auth.handle(url: url)
        switch result {
        case .passwordRecovery: phase = .passwordRecovery
        case .failed(let message):
            recoveryPending = false
            authNotice = "That link has expired or was already used. \(message)"
        case .signedIn, .notAuth: recoveryPending = false
        }
    }

    func passwordUpdated() async {
        recoveryPending = false
        authNotice = "Password updated."
        if let uid = userId { await apply(.signedIn(userId: uid, email: email)) }
    }

    func completeOnboarding() {
        phase = .ready
    }

    func signOut() async {
        try? await auth.signOut()
    }
}

/// Local-only auth used in demo mode.
final class DemoAuthService: AuthServicing, @unchecked Sendable {
    private let demoUser = UUID(uuidString: "00000000-0000-0000-0000-00000000DE70")!
    private var continuation: AsyncStream<AuthEvent>.Continuation?
    private lazy var stream: AsyncStream<AuthEvent> = AsyncStream { c in
        self.continuation = c
        c.yield(.signedOut)
    }

    var events: AsyncStream<AuthEvent> { stream }
    func signIn(email: String, password: String) async throws { continuation?.yield(.signedIn(userId: demoUser, email: email)) }
    func signUp(email: String, password: String, fullName: String?) async throws -> Bool {
        continuation?.yield(.signedIn(userId: demoUser, email: email)); return false
    }
    func sendPasswordReset(email: String) async throws {}
    func updatePassword(_ newPassword: String) async throws {}
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws { try await signIn(email: "", password: "") }
    func signInWithGoogle(idToken: String, accessToken: String?) async throws { try await signIn(email: "", password: "") }
    func handle(url: URL) async -> DeepLinkResult { .notAuth }
    func signOut() async throws { continuation?.yield(.signedOut) }
}
