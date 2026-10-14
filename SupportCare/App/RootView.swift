import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                LaunchView().transition(.opacity)
            case .misconfigured(let message):
                AuthView(configMessage: message).transition(.opacity)
            case .signedOut:
                AuthView().transition(.opacity)
            case .passwordRecovery:
                NewPasswordView().transition(.move(edge: .bottom).combined(with: .opacity))
            case .onboarding:
                if let store = model.store {
                    OnboardingView(store: store).transition(.blurReplace)
                }
            case .ready:
                if let store = model.store {
                    MainTabView()
                        .environment(store)
                        .transition(.blurReplace)
                }
            }
        }
        .animation(Motion.smooth, value: model.phase)
    }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.clipboard.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.primary)
                .symbolEffect(.pulse, options: .repeating)
            Text("Support Care").font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
