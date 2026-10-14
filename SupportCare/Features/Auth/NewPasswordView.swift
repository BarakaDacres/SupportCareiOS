import SwiftUI

/// Shown after opening supportcare://reset-password from the reset email.
struct NewPasswordView: View {
    @Environment(AppModel.self) private var app
    @State private var password = ""
    @State private var confirm = ""
    @State private var isBusy = false
    @State private var error: String?
    @State private var done = false

    private var valid: Bool { password.count >= 8 && password == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password).textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirm).textContentType(.newPassword)
                } header: {
                    Text("Choose a new password")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("At least 8 characters", systemImage: password.count >= 8 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(password.count >= 8 ? Theme.money : .secondary)
                        Label("Passwords match", systemImage: !confirm.isEmpty && password == confirm ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(!confirm.isEmpty && password == confirm ? Theme.money : .secondary)
                    }
                    .contentTransition(.symbolEffect(.replace))
                    .animation(Motion.snappy, value: valid)
                }
                if let error { Section { Banner(kind: .error, text: error) } }
            }
            .navigationTitle("Reset password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { Task { await app.signOut() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Save") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!valid || isBusy)
                }
            }
            .sensoryFeedback(.success, trigger: done)
        }
    }

    private func save() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await app.auth.updatePassword(password)
            done = true
            await app.passwordUpdated()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
