# Supabase iOS (supabase-swift) Research

## Scope
This document captures **verified** setup/API patterns for building the iOS app with `supabase-swift`, including auth, database, realtime, and notification integration strategy.

## Primary Sources
- Supabase Swift reference:
  - https://supabase.com/docs/reference/swift/installing
  - https://supabase.com/docs/reference/swift/initializing
  - https://supabase.com/docs/reference/swift/auth-signup
  - https://supabase.com/docs/reference/swift/auth-signinwithpassword
  - https://supabase.com/docs/reference/swift/auth-signinwithoauth
  - https://supabase.com/docs/reference/swift/select
  - https://supabase.com/docs/reference/swift/subscribe
- supabase-swift repo:
  - https://github.com/supabase/supabase-swift
- Supabase guides:
  - https://supabase.com/docs/guides/realtime/postgres-changes
  - https://supabase.com/docs/guides/functions/examples/push-notifications

## 1) Setup (SPM + Client Initialization)

### Documentation excerpts
From Supabase Swift Installing docs:
- The package can be added as full `Supabase` product or modular products (`Auth`, `Realtime`, `Postgrest`, `Functions`, `Storage`).

From supabase-swift README (requirements):
- iOS 13.0+
- Xcode 15.3+
- Swift 5.10+

### Package pattern
```swift
let package = Package(
    dependencies: [
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .target(
            name: "YourTargetName",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ]
        )
    ]
)
```

### Initialization pattern
```swift
import Supabase

let supabase = SupabaseClient(
  supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
  supabaseKey: "publishable-or-anon-key",
  options: SupabaseClientOptions(
    db: .init(schema: "public"),
    auth: .init(flowType: .pkce)
  )
)
```

## 2) Authentication

## Email/Password (docs examples)
```swift
try await supabase.auth.signUp(
  email: "example@email.com",
  password: "example-password"
)

try await supabase.auth.signIn(
  email: "example@email.com",
  password: "example-password"
)
```

### Verified API signatures (from source)
From `Sources/Auth/AuthClient.swift`:
```swift
public func signUp(
  email: String,
  password: String,
  data: [String: AnyJSON]? = nil,
  redirectTo: URL? = nil,
  captchaToken: String? = nil
) async throws -> AuthResponse

public func signIn(
  email: String,
  password: String,
  captchaToken: String? = nil
) async throws -> Session
```

### Signup gotcha (docs)
`auth-signup` docs explicitly note confirm-email behavior:
- Confirm email enabled: `user` returned, `session` is null.
- Confirm email disabled: `user` and `session` returned.

## Google OAuth

### Option A: Supabase OAuth flow (browser-based)
`auth-signinwithoauth` docs show:
```swift
let session = try await supabase.auth.signInWithOAuth(
  provider: .github
) { (session: ASWebAuthenticationSession) in
  // customize session
}
```
For Google, use the same API with `provider: .google`.

### Option B: Native Google Sign-In -> Supabase ID token exchange
Verified from source:
```swift
public func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session
```
And `OpenIDConnectCredentials` supports provider `google`:
```swift
public enum Provider: String, Codable, Hashable, Sendable {
  case google, apple, azure, facebook
}
```

Pattern:
```swift
let credentials = OpenIDConnectCredentials(
  provider: .google,
  idToken: googleIDToken,
  accessToken: googleAccessToken
)
let session = try await supabase.auth.signInWithIdToken(credentials: credentials)
```

### OAuth-related source signatures
```swift
nonisolated public func getOAuthSignInURL(
  provider: Provider,
  scopes: String? = nil,
  redirectTo: URL? = nil,
  queryParams: [(name: String, value: String?)] = []
) throws -> URL

public func signInWithOAuth(
  provider: Provider,
  redirectTo: URL? = nil,
  scopes: String? = nil,
  queryParams: [(name: String, value: String?)] = [],
  launchFlow: @MainActor @Sendable (_ url: URL) async throws -> URL
) async throws -> Session
```

## 3) Database Query Patterns

### Fetch data (docs example)
```swift
struct Instrument: Decodable {
  let id: Int
  let name: String
}

let instruments: [Instrument] = try await supabase
  .from("instruments")
  .select()
  .execute()
  .value
```

### Filtered select / specific columns
```swift
let instruments: [Instrument] = try await supabase
  .from("instruments")
  .select("name")
  .execute()
  .value
```

### Operational notes
- Docs state default row return limit is 1000 (configurable).
- `select()` can be combined with filters/modifiers.
- In production for this app, all booking/profile access must rely on RLS policies.

## 4) Realtime Subscriptions

### Docs pattern (Swift `subscribe` reference)
```swift
let channel = supabase.channel("channelId")
let changeStream = channel.postgresChange(AnyAction.self, schema: "public")

await channel.subscribe()

for await change in changeStream {
  switch change {
  case .delete(let action): print(action.oldRecord)
  case .insert(let action): print(action.record)
  case .update(let action): print(action.record)
  case .select(let action): print(action.record)
  }
}
```

### Verified signatures (source)
From `RealtimeChannel+AsyncAwait.swift`:
```swift
public func postgresChange(
  _: AnyAction.Type,
  schema: String = "public",
  table: String? = nil,
  filter: RealtimePostgresFilter? = nil
) -> AsyncStream<AnyAction>
```

From `SupabaseClient.swift`:
```swift
public func channel(
  _ name: String,
  options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
) -> RealtimeChannelV2
```

### Realtime setup requirement
From Postgres Changes guide:
- Table must be in publication `supabase_realtime`.
- RLS must allow the subscribing user to read changed rows.

## 5) Push Notifications via Supabase (Important)

### What Supabase documents directly
The "Sending Push Notifications" guide demonstrates:
- Supabase Edge Function
- Database webhook trigger
- Sending push through Expo/FCM providers

Example excerpt (Edge Function style):
```ts
const { data } = await supabase
  .from('profiles')
  .select('expo_push_token')
  .eq('id', payload.record.user_id)
  .single()
```

## iOS-native implication
Supabase does **not** provide an APNs broker inside `supabase-swift` itself. For native iOS APNs, recommended architecture is:
1. App registers APNs token with your backend (Supabase table).
2. Booking events insert into `notifications` table.
3. DB trigger/webhook invokes Edge Function.
4. Edge Function calls push provider/APNs pipeline.

## 6) High-Value Gotchas for iOS
- Configure deep-link redirect URL for OAuth and PKCE flow before testing.
- Confirm-email behavior changes expected `signUp` result (`session` may be null).
- `onAuthStateChange` emits `.initialSession`; session may already be expired and refresh can follow.
- Realtime updates only fire for tables in `supabase_realtime` and rows visible under RLS.
- Keep anon key in app; never embed service role key in iOS binary.
