import AuthenticationServices
import SupportCareServices
import SwiftUI

/// Sign in / Create account / Forgot password, plus Apple & Google (port of AuthPage.tsx).
struct AuthView: View {
    @Environment(AppModel.self) private var app
    var configMessage: String? = nil

    var body: some View {
        AuthScreen(auth: app.auth, configMessage: configMessage)
    }
}

private struct AuthScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @State private var vm: AuthViewModel
    @State private var apple = AppleSignInCoordinator()
    @FocusState private var focus: Field?
    let configMessage: String?

    enum Field { case name, email, password }

    init(auth: AuthServicing, configMessage: String?) {
        _vm = State(initialValue: AuthViewModel(auth: auth))
        self.configMessage = configMessage
    }

    var body: some View {
        @Bindable var bvm = vm
        ScrollView {
            VStack(spacing: 28) {
                header
                if let configMessage {
                    VStack(spacing: 10) {
                        Banner(kind: .info, text: "Supabase isn't configured. \(configMessage)")
                        Button("Explore demo with sample data") { app.enterDemoMode() }
                            .buttonStyle(.glassProminent)
                    }
                }
                if let notice = app.authNotice { Banner(kind: .info, text: notice) }

                GlassSegmentedControl(options: [AuthViewModel.Mode.signIn, .signUp], selection: Binding(
                    get: { bvm.mode == .forgot ? .signIn : bvm.mode },
                    set: { bvm.mode = $0 }), title: \.title)

                form(bvm)

                if vm.mode != .forgot { socialButtons(vm) }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .animation(Motion.smooth, value: vm.mode)
            .animation(Motion.smooth, value: vm.error)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(alignment: .top) { backdrop }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.clipboard.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .glassEffect(.regular.tint(Theme.primary), in: .rect(cornerRadius: 28))
                .symbolEffect(.bounce, value: vm.mode)
            Text("Support Care").font(.largeTitle.bold())
            Text("Shifts, NDIS invoices and income, sorted.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func form(_ vm: AuthViewModel) -> some View {
        @Bindable var vm = vm
        VStack(spacing: 14) {
            if vm.mode == .forgot {
                Text("Enter your email and we'll send a link to reset your password.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if vm.mode == .signUp {
                field("Full name", systemImage: "person") {
                    TextField("Full name", text: $vm.fullName).textContentType(.name).focused($focus, equals: .name)
                }
            }
            field("Email", systemImage: "envelope") {
                TextField("Email", text: $vm.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .email)
            }
            if vm.mode != .forgot {
                field("Password", systemImage: "lock") {
                    SecureField(vm.mode == .signUp ? "Password (8+ characters)" : "Password", text: $vm.password)
                        .textContentType(vm.mode == .signUp ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .onSubmit { Task { await vm.submit() } }
                }
            }
            if let error = vm.error { Banner(kind: .error, text: error) }
            if let message = vm.message { Banner(kind: .success, text: message) }

            Button {
                focus = nil
                Task { await vm.submit() }
            } label: {
                ZStack {
                    Text(vm.mode == .forgot ? "Send reset link" : vm.mode.title).opacity(vm.isBusy ? 0 : 1)
                    if vm.isBusy { ProgressView() }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(!vm.canSubmit)

            HStack {
                if vm.mode == .signIn {
                    Button("Forgot password?") { vm.mode = .forgot }
                } else if vm.mode == .forgot {
                    Button("Back to sign in", systemImage: "chevron.left") { vm.mode = .signIn }
                }
                Spacer()
            }
            .font(.footnote.weight(.medium))
        }
    }

    private func field<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 20)
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(.background.secondary, in: .rect(cornerRadius: Theme.radius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func socialButtons(_ vm: AuthViewModel) -> some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle().frame(height: 0.5).foregroundStyle(.separator)
                Text("or").font(.footnote).foregroundStyle(.secondary)
                Rectangle().frame(height: 0.5).foregroundStyle(.separator)
            }
            SignInWithAppleButton(.signIn) { request in
                apple.prepare(request)
            } onCompletion: { result in
                do {
                    if let credential = try apple.credential(from: result) {
                        Task { await vm.apple(credential) }
                    }
                } catch { vm.error = AuthViewModel.friendly(error) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(.capsule)
            .overlay(alignment: .trailing) { lastUsed("apple", vm) }

            if GoogleSignInCoordinator.isConfigured || app.isDemo {
                GoogleSignInButton { Task { await vm.google() } }
                    .overlay(alignment: .trailing) { lastUsed("google", vm) }
            }
        }
        .disabled(vm.isBusy)
    }

    @ViewBuilder
    private func lastUsed(_ provider: String, _ vm: AuthViewModel) -> some View {
        if vm.lastProvider == provider {
            Badge(text: "Last used", color: Theme.primary).padding(.trailing, 14)
        }
    }

    private var backdrop: some View {
        LinearGradient(colors: [Theme.primary.opacity(0.35), Theme.purple.opacity(0.15), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 420)
            .ignoresSafeArea()
    }
}

#Preview {
    AuthView().environment(AppModel.demo())
}
