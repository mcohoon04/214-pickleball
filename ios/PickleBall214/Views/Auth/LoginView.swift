import SwiftUI
import GoogleSignInSwift
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthService.self) var authService
    @State private var inviteCode = ""
    @State private var isCodeValid = false
    @State private var isValidating = false
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var currentNonce: String?
    @State private var showForgotPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)

                    // App title
                    Text("214 Pickle")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Theme.accent)

                    Text("Court Scheduling")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)

                    Spacer().frame(height: 20)

                    if !isCodeValid {
                        // MARK: - Invite Code Gate
                        VStack(spacing: 16) {
                            Text("Enter your invite code to continue")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)

                            TextField("Invite Code", text: $inviteCode)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.center)
                                .font(.title3.monospaced())
                                .padding()
                                .background(Theme.surface)
                                .cornerRadius(Theme.cornerRadius)
                                .foregroundStyle(Theme.textPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                        .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                                )

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(Theme.destructive)
                            }

                            Button {
                                validateCode()
                            } label: {
                                Group {
                                    if isValidating {
                                        ProgressView().tint(Theme.textOnAccent)
                                    } else {
                                        Text("Continue")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(inviteCode.isEmpty ? Theme.disabled : Theme.accent)
                                .foregroundStyle(Theme.textOnAccent)
                                .cornerRadius(Theme.cornerRadius)
                            }
                            .disabled(inviteCode.isEmpty || isValidating)
                        }
                    } else {
                        // MARK: - Sign In (unlocked after valid code)

                        // Email & Password
                        VStack(spacing: 12) {
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

                        // Error
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.destructive)
                        }

                        // Sign In button
                        Button {
                            signIn()
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(Theme.textOnAccent)
                                } else {
                                    Text("Sign In")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accent)
                            .foregroundStyle(Theme.textOnAccent)
                            .cornerRadius(Theme.cornerRadius)
                        }
                        .disabled(email.isEmpty || password.isEmpty || isLoading)

                        // Forgot password
                        Button {
                            resetEmail = email
                            showForgotPassword = true
                        } label: {
                            Text("Forgot Password?")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                        }

                        // Divider
                        HStack {
                            Rectangle().frame(height: 1).foregroundStyle(Theme.surface)
                            Text("or").foregroundStyle(Theme.textSecondary).font(.caption)
                            Rectangle().frame(height: 1).foregroundStyle(Theme.surface)
                        }

                        // Apple Sign In
                        SignInWithAppleButton(.signIn) { request in
                            let nonce = AuthService.randomNonce()
                            currentNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = AuthService.sha256(nonce)
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .cornerRadius(Theme.cornerRadius)

                        // Google Sign In
                        GoogleSignInButton(scheme: .light, style: .wide, action: signInWithGoogle)
                            .frame(height: 50)
                            .cornerRadius(Theme.cornerRadius)

                        Spacer()

                        // Sign Up link
                        NavigationLink {
                            SignUpView()
                                .environment(authService)
                        } label: {
                            HStack {
                                Text("Don't have an account?")
                                    .foregroundStyle(Theme.textSecondary)
                                Text("Sign Up")
                                    .foregroundStyle(Theme.accent)
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal, Theme.padding)
            }
            .background(Theme.background.ignoresSafeArea())
            .alert("Reset Password", isPresented: $showForgotPassword) {
                TextField("Email", text: $resetEmail)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Send Reset Link") {
                    Task {
                        do {
                            try await authService.resetPassword(email: resetEmail)
                            resetSent = true
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter your email and we'll send you a password reset link.")
            }
            .alert("Check Your Email", isPresented: $resetSent) {
                Button("OK") {}
            } message: {
                Text("If an account exists with that email, you'll receive a password reset link shortly.")
            }
        }
    }

    private func validateCode() {
        isValidating = true
        errorMessage = nil
        Task {
            do {
                let valid: Bool = try await SupabaseConfig.client
                    .rpc("validate_invite_code", params: ["p_code": inviteCode])
                    .execute()
                    .value
                if valid {
                    withAnimation { isCodeValid = true }
                } else {
                    errorMessage = "Invalid invite code"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isValidating = false
        }
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signInWithGoogle()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let nonce = currentNonce else { return }
            Task {
                do {
                    try await authService.signInWithApple(authorization: authorization, rawNonce: nonce)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
