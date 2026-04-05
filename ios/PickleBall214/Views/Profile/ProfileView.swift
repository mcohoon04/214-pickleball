import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) var authService
    @Environment(\.dismiss) var dismiss
    @State private var displayName = ""
    @State private var pushEnabled = true
    @State private var emailEnabled = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Avatar
                Circle()
                    .fill(Theme.accent.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text(String(displayName.prefix(1)).uppercased())
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.accent)
                    )
                    .padding(.top, 20)

                // Display Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    TextField("Your name", text: $displayName)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .background(Theme.surface)
                        .cornerRadius(Theme.cornerRadius)
                        .foregroundStyle(Theme.textPrimary)
                }

                // Email (read-only)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Text(authService.currentEmail ?? "—")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .cornerRadius(Theme.cornerRadius)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Notifications
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    VStack(spacing: 0) {
                        Toggle(isOn: $pushEnabled) {
                            Label("Push Notifications", systemImage: "bell.fill")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.accent)
                        .padding()

                        Divider().background(Theme.background)

                        Toggle(isOn: $emailEnabled) {
                            Label("Email Notifications", systemImage: "envelope.fill")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.accent)
                        .padding()
                    }
                    .background(Theme.surface)
                    .cornerRadius(Theme.cornerRadius)
                }

                // Error / Success
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                }

                // Save button
                Button {
                    save()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(Theme.textOnAccent)
                        } else {
                            Text("Save Changes")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .foregroundStyle(Theme.textOnAccent)
                    .cornerRadius(Theme.cornerRadius)
                }
                .disabled(isSaving || displayName.isEmpty)

                Spacer().frame(height: 20)

                // Sign out
                Button {
                    signOut()
                } label: {
                    Text("Sign Out")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.surface)
                        .foregroundStyle(Theme.destructive)
                        .cornerRadius(Theme.cornerRadius)
                }
            }
            .padding(.horizontal, Theme.padding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Theme.accent)
            }
        }
        .alert("Saved", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your profile has been updated.")
        }
        .onAppear {
            if let profile = authService.currentUser {
                displayName = profile.displayName
                pushEnabled = profile.pushEnabled
                emailEnabled = profile.emailEnabled
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await authService.updateProfile(
                    displayName: displayName,
                    pushEnabled: pushEnabled,
                    emailEnabled: emailEnabled
                )
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func signOut() {
        Task {
            try? await authService.signOut()
            dismiss()
        }
    }
}
