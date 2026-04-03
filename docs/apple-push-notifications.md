# Apple Push Notifications (APNs) Research

## Scope
This document covers APNs setup for iOS, including:
- APNs auth keys vs TLS certificates
- Apple Developer + Xcode configuration
- device token registration flow
- Supabase integration strategy

## Primary Sources
- Apple: Registering/handling remote notifications (archived programming guide)
  - https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/HandlingRemoteNotifications.html
- Apple: Enable app capabilities
  - https://developer.apple.com/help/account/identifiers/enable-app-capabilities/
- Apple: APNs auth tokens
  - https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/
- Apple: APNs TLS certificate
  - https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-a-tls-certificate/

## 1) APNs Authentication: Key vs Certificate

## Auth Key (recommended modern default)
From Apple "Communicate with APNs using authentication tokens":
- "You can use one APNs signing key to authenticate tokens for multiple apps."
- "The signing key works for both the development and production environments."
- "The signing key doesn’t expire, but can be revoked."

Operationally:
- Create APNs-enabled private key in Apple Developer account.
- Keep `Key ID`, `Team ID`, and `.p8` private key.
- Your provider creates JWT and uses HTTP/2 APNs API.

## TLS Certificate
From Apple "Communicate with APNs using a TLS certificate":
- APNs can be used via client TLS certificate.
- Generate a separate APNs client TLS cert per app.
- Export cert+private key identity as `.p12` for server installation.

Operational tradeoff:
- More certificate lifecycle work (generation/export/rotation).
- Usually less convenient than auth key for new systems.

## Recommendation for this project
Use **APNs auth key** unless a vendor/provider explicitly requires cert workflow.

## 2) Apple Developer Portal Configuration

## Enable capability for App ID
From Apple "Enable app capabilities":
1. In Certificates, Identifiers & Profiles -> `Identifiers`.
2. Select App ID, click `Edit`.
3. Enable required capability checkboxes (including Push Notifications).
4. Click `Save` / `Confirm`.

Important Apple note:
- Changing capabilities can invalidate provisioning profiles.
- Regenerate affected provisioning profiles after App ID capability changes.

## 3) Xcode Project Configuration

From Apple remote notifications guide:
- App must have proper entitlements to talk to APNs.
- Entitlement is added in Xcode Capabilities pane.
- Apps without required entitlements can be rejected in App Review.

Practical Xcode checklist:
1. Open app target -> `Signing & Capabilities`.
2. Add `Push Notifications` capability.
3. Add `Background Modes` -> enable `Remote notifications` if needed for background handling.
4. Ensure signing team/profile includes updated App ID capabilities.

## 4) Registering for Device Tokens (App Runtime)

From Apple remote notifications guide:
- Call `registerForRemoteNotifications` at app launch.
- Handle:
  - `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
  - `application(_:didFailToRegisterForRemoteNotificationsWithError:)`
- "Never cache device tokens" in app; always re-fetch from system when needed.

Example pattern (Apple listing style):
```swift
UIApplication.shared.registerForRemoteNotifications()

func application(
  _ application: UIApplication,
  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
  // forward token to your provider/backend
  forwardTokenToServer(token: deviceToken)
}

func application(
  _ application: UIApplication,
  didFailToRegisterForRemoteNotificationsWithError error: Error
) {
  // degrade gracefully / disable remote-notification-dependent features
}
```

Also from Apple docs:
- APNs device tokens are variable length; do not hard-code token size.
- Token may change; app can receive registration callback again.

## 5) Supabase Integration Pattern

Supabase does not ship an iOS APNs sender in `supabase-swift`.
Use this architecture:
1. iOS app gets APNs token and sends it to Supabase (`device_tokens` table).
2. Booking events create notification jobs (`notifications` table).
3. Postgres trigger/webhook invokes Edge Function.
4. Edge Function calls APNs provider endpoint (or push service abstraction).
5. Edge Function updates delivery status in `notifications`.

If using Expo/React Native, Supabase docs show an Expo-token flow with DB webhook + Edge Function. For native iOS, replace Expo token send step with APNs token handling.

## 6) Provisioning Profile Notes
- After enabling Push Notifications capability, regenerate profiles if Apple marks them invalid.
- For Ad Hoc/internal testing, ensure exported build uses profiles containing Push entitlement.
- For TestFlight/App Store distribution, ensure App Store Connect profile reflects latest capabilities.
