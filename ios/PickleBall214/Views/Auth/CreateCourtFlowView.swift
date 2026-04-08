import SwiftUI
import GoogleSignInSwift
import AuthenticationServices

struct CreateCourtFlowView: View {
    @Environment(AuthService.self) var authService
    @Environment(\.dismiss) var dismiss
    @State private var step: FlowStep = .signUp
    @State private var currentNonce: String?

    // Sign up fields
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""

    // Court fields
    @State private var courtName = ""
    @State private var courtCode = ""

    // Shared state
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var createdCode: String?

    enum FlowStep {
        case signUp
        case createCourt
        case done
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch step {
                case .signUp:
                    signUpStep
                case .createCourt:
                    createCourtStep
                case .done:
                    doneStep
                }
            }
            .padding(.horizontal, Theme.padding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if step == .signUp {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuth in
            if isAuth && step == .signUp {
                withAnimation { step = .createCourt }
            }
        }
    }

    // MARK: - Step 1: Sign Up

    private var signUpStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)

            Text("Create Your Court")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("First, create your account")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 12) {
                TextField("Your Name", text: $displayName)
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

                SecureField("Password (min 6 characters)", text: $password)
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
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isSignUpValid ? Theme.accent : Theme.disabled)
                .foregroundStyle(Theme.textOnAccent)
                .cornerRadius(Theme.cornerRadius)
            }
            .disabled(!isSignUpValid || isLoading)

            HStack {
                Rectangle().frame(height: 1).foregroundStyle(Theme.surface)
                Text("or").foregroundStyle(Theme.textSecondary).font(.caption)
                Rectangle().frame(height: 1).foregroundStyle(Theme.surface)
            }

            SignInWithAppleButton(.signUp) { request in
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

            GoogleSignInButton(scheme: .light, style: .wide, action: signInWithGoogle)
                .frame(height: 50)
                .cornerRadius(Theme.cornerRadius)
        }
    }

    // MARK: - Step 2: Create Court

    private var createCourtStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)

            Text("Set Up Your Court")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Give your court a name and create a code to share with your players")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("Court Name (e.g., Backyard Court)", text: $courtName)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .padding()
                    .background(Theme.surface)
                    .cornerRadius(Theme.cornerRadius)
                    .foregroundStyle(Theme.textPrimary)

                TextField("Court Code (e.g., PICKLE214)", text: $courtCode)
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

                Text("4-20 characters. Players use this code to join.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
            }

            Button {
                createCourt()
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(Theme.textOnAccent)
                    } else {
                        Text("Create Court")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isCourtValid ? Theme.accent : Theme.disabled)
                .foregroundStyle(Theme.textOnAccent)
                .cornerRadius(Theme.cornerRadius)
            }
            .disabled(!isCourtValid || isLoading)
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)

            Text("Court Created!")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Share this code with your players:")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Text(createdCode ?? "")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding()
                .background(Theme.surface)
                .cornerRadius(Theme.cornerRadius)

            // Share button
            if let code = createdCode {
                ShareLink(item: "Join my pickleball court on 214 Pickle! Use court code: \(code)") {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Code")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .foregroundStyle(Theme.textOnAccent)
                    .cornerRadius(Theme.cornerRadius)
                }
            }

            // This view will disappear when authService.isAuthenticated triggers MainView
        }
    }

    // MARK: - Validation

    private var isSignUpValid: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 6
    }

    private var isCourtValid: Bool {
        courtName.count >= 2 && courtCode.count >= 4 && courtCode.count <= 20
    }

    // MARK: - Actions

    private func signUp() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signUp(email: email, password: password, displayName: displayName)
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

    private func createCourt() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let code: String = try await SupabaseConfig.client
                    .rpc("create_court", params: ["p_court_name": courtName, "p_code": courtCode])
                    .execute()
                    .value
                createdCode = code
                withAnimation { step = .done }
            } catch {
                if "\(error)".contains("already taken") {
                    errorMessage = "This court code is already taken. Try a different one."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}
