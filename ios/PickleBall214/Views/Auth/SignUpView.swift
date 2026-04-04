import SwiftUI

struct SignUpView: View {
    @Environment(AuthService.self) var authService
    @Environment(\.dismiss) var dismiss
    @State private var inviteCode = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Text("Create Account")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Enter your invite code to get started")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                VStack(spacing: 12) {
                    TextField("Invite Code", text: $inviteCode)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Theme.surface)
                        .cornerRadius(Theme.cornerRadius)
                        .foregroundStyle(Theme.textPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                        )

                    TextField("Display Name", text: $displayName)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .background(Theme.surface)
                        .cornerRadius(Theme.cornerRadius)
                        .foregroundStyle(Theme.textPrimary)

                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Theme.surface)
                        .cornerRadius(Theme.cornerRadius)
                        .foregroundStyle(Theme.textPrimary)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Theme.surface)
                        .cornerRadius(Theme.cornerRadius)
                        .foregroundStyle(Theme.textPrimary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                }

                Button {
                    signUp()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(Theme.textOnAccent)
                        } else {
                            Text("Create Account")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFormValid ? Theme.accent : Theme.disabled)
                    .foregroundStyle(Theme.textOnAccent)
                    .cornerRadius(Theme.cornerRadius)
                }
                .disabled(!isFormValid || isLoading)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    HStack {
                        Text("Already have an account?")
                            .foregroundStyle(Theme.textSecondary)
                        Text("Sign In")
                            .foregroundStyle(Theme.accent)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, Theme.padding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !inviteCode.isEmpty && !displayName.isEmpty && !email.isEmpty && password.count >= 6
    }

    private func signUp() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signUp(
                    email: email,
                    password: password,
                    displayName: displayName,
                    inviteCode: inviteCode
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
