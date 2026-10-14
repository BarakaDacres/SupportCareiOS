import SwiftUI
import GoogleSignIn

@main
struct SupportCareApp: App {
    @State private var model = AppModel.live()
    @AppStorage("appearance") private var appearance: AppearancePreference = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.primary)
                .onOpenURL { url in
                    // Google Sign-In callback, otherwise a Supabase auth deep link.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    Task { await model.handle(url: url) }
                }
                .task { await model.start() }
        }
    }
}
