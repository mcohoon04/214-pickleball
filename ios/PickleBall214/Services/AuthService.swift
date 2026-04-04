import Foundation
import Supabase
import GoogleSignIn
import AuthenticationServices
import CryptoKit

@Observable
final class AuthService {
    var currentUser: Profile?
    var isAuthenticated = false
    var isLoading = true

    private let supabase = SupabaseConfig.client

    init() {
        Task { await listenForAuthChanges() }
    }

    private func listenForAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            await MainActor.run {
                switch event {
                case .initialSession:
                    self.isAuthenticated = session != nil
                    self.isLoading = false
                case .signedIn:
                    self.isAuthenticated = true
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentUser = nil
                default:
                    break
                }
            }
            if session != nil {
                await loadProfile()
            }
        }
    }

    // MARK: - Email/Password

    func signUp(email: String, password: String, displayName: String, inviteCode: String) async throws {
        let isValid: Bool = try await supabase
            .rpc("validate_invite_code", params: ["p_code": inviteCode])
            .execute()
            .value
        guard isValid else { throw AuthError.invalidInviteCode }

        try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(displayName)]
        )
    }

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async throws {
        guard let windowScene = await MainActor.run(body: {
            UIApplication.shared.connectedScenes.first as? UIWindowScene
        }),
        let rootVC = await MainActor.run(body: { windowScene.windows.first?.rootViewController }) else {
            throw AuthError.googleSignInFailed
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.googleSignInFailed
        }

        try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
        )
    }

    // MARK: - Apple Sign-In

    func signInWithApple(authorization: ASAuthorization, rawNonce: String) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.appleSignInFailed
        }

        try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )

        // Apple only provides name on first sign-in — capture it
        if let fullName = credential.fullName {
            var parts: [String] = []
            if let given = fullName.givenName { parts.append(given) }
            if let family = fullName.familyName { parts.append(family) }
            let name = parts.joined(separator: " ")
            if !name.isEmpty {
                try? await updateProfile(displayName: name)
            }
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await supabase.auth.signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Profile

    func loadProfile() async {
        guard let userId = try? await supabase.auth.session.user.id else { return }
        do {
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            await MainActor.run { self.currentUser = profile }
        } catch {
            print("Failed to load profile: \(error)")
        }
    }

    func updateProfile(displayName: String? = nil, pushEnabled: Bool? = nil, emailEnabled: Bool? = nil) async throws {
        guard let userId = currentUser?.id else { return }
        var updates: [String: AnyJSON] = [:]
        if let displayName { updates["display_name"] = .string(displayName) }
        if let pushEnabled { updates["push_enabled"] = .bool(pushEnabled) }
        if let emailEnabled { updates["email_enabled"] = .bool(emailEnabled) }
        guard !updates.isEmpty else { return }

        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId)
            .execute()

        await loadProfile()
    }

    func updateDeviceToken(_ token: String) async throws {
        guard let userId = currentUser?.id else { return }
        try await supabase
            .from("profiles")
            .update(["apns_device_token": token])
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case invalidInviteCode
        case googleSignInFailed
        case appleSignInFailed

        var errorDescription: String? {
            switch self {
            case .invalidInviteCode: return "Invalid invite code"
            case .googleSignInFailed: return "Google sign-in failed"
            case .appleSignInFailed: return "Apple sign-in failed"
            }
        }
    }
}
