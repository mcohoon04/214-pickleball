import SwiftUI

struct ProfileView: View {
    @Environment(AuthService.self) var authService
    @Environment(\.dismiss) var dismiss
    @State private var displayName = ""
    @State private var pushEnabled = true
    @State private var emailEnabled = true
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            // Profile section
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(Theme.accent.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.title2.bold())
                                .foregroundStyle(Theme.accent)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Display Name", text: $displayName)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        if let email = authService.currentUser?.id.uuidString {
                            Text("ID: \(email.prefix(8))...")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }

            // Notifications section
            Section("Notifications") {
                Toggle(isOn: $pushEnabled) {
                    Label("Push Notifications", systemImage: "bell.fill")
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.surface)

                Toggle(isOn: $emailEnabled) {
                    Label("Email Notifications", systemImage: "envelope.fill")
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.surface)
            }

            // Save button
            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().tint(Theme.textOnAccent)
                        } else {
                            Text("Save Changes")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.accent)
                .foregroundStyle(Theme.textOnAccent)
                .disabled(isSaving)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.destructive)
                        .font(.caption)
                        .listRowBackground(Theme.background)
                }
            }

            // Sign out
            Section {
                Button {
                    signOut()
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .foregroundStyle(Theme.destructive)
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Theme.accent)
            }
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
                dismiss()
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
