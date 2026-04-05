# Google Sign-In iOS SDK Research

## Scope
Native Google Sign-In for iOS, integrated with Supabase `signInWithIdToken` for authentication.

## Primary Sources
- Google Sign-In iOS start guide:
  - https://developers.google.com/identity/sign-in/ios/start-integrating
- Google Sign-In iOS sign-in flow:
  - https://developers.google.com/identity/sign-in/ios/sign-in
- Google Sign-In iOS backend auth (ID token):
  - https://developers.google.com/identity/sign-in/ios/backend-auth
- GoogleSignIn-iOS GitHub repo:
  - https://github.com/google/GoogleSignIn-iOS
- Supabase Swift OAuth reference:
  - https://supabase.com/docs/reference/swift/auth-signinwithoauth

## 1) SDK Installation (SPM)

Package URL: `https://github.com/google/GoogleSignIn-iOS`
Current version: 9.0.0

Add two products:
- `GoogleSignIn` — core sign-in functionality
- `GoogleSignInSwift` — SwiftUI button components

## 2) Google Cloud Console Setup

1. Go to Google Cloud Console → APIs & Services → Credentials.
2. Create an **iOS** OAuth 2.0 Client ID (needs bundle ID).
3. Note the **iOS Client ID** (used in app).
4. If backend token verification is needed, also create a **Web application** Client ID (server client ID).

## 3) Info.plist Configuration

```xml
<key>GIDClientID</key>
<string>YOUR_IOS_CLIENT_ID</string>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>YOUR_DOT_REVERSED_IOS_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

The reversed client ID format: `com.googleusercontent.apps.1234567890-abcdefg`

Optional — if using server client ID for backend auth:
```xml
<key>GIDServerClientID</key>
<string>YOUR_SERVER_CLIENT_ID</string>
```

## 4) SwiftUI App Entry Point

Handle the OAuth callback URL and restore previous sign-in:

```swift
import GoogleSignIn

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                        // Check if `user` exists; otherwise, handle `error`
                    }
                }
        }
    }
}
```

## 5) SwiftUI Sign-In Button

```swift
import GoogleSignInSwift

GoogleSignInButton(action: handleSignInButton)

func handleSignInButton() {
    GIDSignIn.sharedInstance.signIn(
        withPresenting: rootViewController
    ) { signInResult, error in
        guard let result = signInResult else {
            // Inspect error
            return
        }
        // Sign in succeeded
    }
}
```

## 6) Getting the ID Token (for Supabase)

```swift
GIDSignIn.sharedInstance.signIn(withPresenting: self) { signInResult, error in
    guard error == nil else { return }
    guard let signInResult = signInResult else { return }

    signInResult.user.refreshTokensIfNeeded { user, error in
        guard error == nil else { return }
        guard let user = user else { return }

        let idToken = user.idToken
        // Send idToken to Supabase signInWithIdToken
    }
}
```

Important from Google docs: "Do not accept plain user IDs on your backend server." Always use the verifiable ID token.

## 7) Supabase Token Exchange

From `supabase-swift` source (verified in `supabase-ios.md`):

```swift
let credentials = OpenIDConnectCredentials(
    provider: .google,
    idToken: idToken.tokenString,
    accessToken: user.accessToken.tokenString
)
let session = try await supabase.auth.signInWithIdToken(credentials: credentials)
```

## 8) Supabase Dashboard Configuration

In Supabase Dashboard → Authentication → Providers → Google:
1. Enable Google provider.
2. Enter the **Web application** Client ID (not the iOS one) as the client ID.
3. Enter the corresponding client secret.
4. The iOS app uses native sign-in → ID token exchange, so the Supabase redirect URL is not used for the native flow.

## 9) Alternative: Browser-Based OAuth (without native Google SDK)

If you want to skip the Google SDK entirely, Supabase supports browser-based OAuth via `ASWebAuthenticationSession`:

```swift
let session = try await supabase.auth.signInWithOAuth(
    provider: .google
) { (session: ASWebAuthenticationSession) in
    // customize session
}
```

Or manual URL flow:
```swift
let url = try await supabase.auth.getOAuthSignInURL(
    provider: .google,
    redirectTo: URL(string: "com.yourapp://callback")
)

let session = ASWebAuthenticationSession(
    url: url,
    callbackURLScheme: "com.yourapp"
) { url, error in
    guard let url else { return }
    Task {
        try await supabase.auth.session(from: url)
    }
}
session.presentationContextProvider = self
session.start()
```

## Recommendation for This App

Use **native Google Sign-In SDK → `signInWithIdToken`** (sections 1-7 above). Reasons:
- Better UX (native Google sign-in sheet, no browser redirect).
- Token exchange is more reliable than browser-based callback parsing.
- Small user base means the extra SDK dependency is fine.

## Gotchas
- Starting May 2024, Apple requires Privacy Manifests — use GoogleSignIn-iOS v7.1.0+.
- Apps must be signed with an Apple certificate for Keychain credential storage.
- `rootViewController` in SwiftUI requires bridging to get the presenting view controller (use `UIApplication.shared.connectedScenes` pattern or a `UIViewControllerRepresentable` wrapper).
