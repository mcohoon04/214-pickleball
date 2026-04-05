# Post-Implementation Changes & Fixes

Changes made after the initial implementation plan (`2026-04-04-implementation-plan.md`) was executed. These must be accounted for in any future platform (Android, web).

---

## Bug Fixes

### 1. iOS Deployment Target: 16.0 → 17.0
- **Problem:** `@Observable` macro requires iOS 17+. Build failed.
- **Fix:** Updated `project.yml` deployment target to iOS 17.0.
- **Impact on future platforms:** Android/web not affected. If backporting iOS to older devices, replace `@Observable` with `ObservableObject`.

### 2. APNs Sandbox → Production
- **Problem:** `APNS_SANDBOX=true` was sending to `api.development.push.apple.com`, but TestFlight/App Store builds get production device tokens.
- **Fix:** Set `APNS_SANDBOX=false` in production secrets.
- **Impact:** Any server sending push notifications must use the production APNs endpoint for App Store/TestFlight builds, sandbox only for Xcode debug builds.

### 3. pg_net Extension Not Enabled
- **Problem:** `pg_cron` job failed with `schema "net" does not exist` because `pg_net` wasn't enabled.
- **Fix:** Enabled `pg_net` extension via Supabase Dashboard.
- **Impact:** When setting up a new Supabase project, manually enable these extensions via Dashboard before deploying:
  - `pg_cron`
  - `pg_net`
  - `pgcrypto` (usually auto-enabled)
  - `supabase_vault` (usually auto-enabled)

### 4. Info.plist Orientations for App Store
- **Problem:** App Store validation rejected upload — required all 4 interface orientations listed.
- **Fix:** Added all orientations to `UISupportedInterfaceOrientations` in Info.plist. App still displays portrait-only via SwiftUI.
- **Impact:** Any iOS submission needs all 4 orientations listed even if the app only uses portrait.

### 5. iPhone-Only (TARGETED_DEVICE_FAMILY)
- **Problem:** Default xcodegen setting was `"1,2"` (iPhone + iPad), requiring iPad screenshots for App Store.
- **Fix:** Set `TARGETED_DEVICE_FAMILY: "1"` (iPhone only). Eliminates iPad screenshot requirement.
- **Impact:** If iPad support is added later, change back to `"1,2"` and provide iPad screenshots.

### 6. CFBundleName Consistency
- **Problem:** `CFBundleName` was "PickleBall214" (internal module name) instead of "214 Pickle".
- **Fix:** Updated to "214 Pickle" in both Info.plist and project.yml.
- **Impact:** Cosmetic — affects how the app name appears in system notifications and settings.

---

## Feature Changes

### 7. Invite Code Gate on Login Screen (Not Just Signup)
- **Problem:** Original design had invite code only on the SignUp screen. Google/Apple sign-in on LoginView bypassed the invite code entirely.
- **Fix:** Moved invite code validation to the LoginView as a gate. User must enter a valid code before ANY sign-in method (email, Google, Apple) or signup link becomes visible.
- **Flow:** Login screen shows invite code field → validate via `validate_invite_code` RPC → on success, reveal email/password fields, Apple, Google, and Sign Up link.
- **SignUp screen:** Invite code field removed (already validated at login gate).
- **Impact on future platforms:** The invite code gate must be the first screen on any client. The `validate_invite_code` RPC is callable by `anon` role (pre-auth).

### 8. Forgot Password
- **Problem:** No way to reset a forgotten password.
- **Fix:** Added "Forgot Password?" link on LoginView. Shows an alert prompting for email, calls `supabase.auth.resetPasswordForEmail(email)`. Shows confirmation message.
- **Impact on future platforms:** Use Supabase's `resetPasswordForEmail` API. The reset email is sent by Supabase Auth using built-in templates.

### 9. Profile View Rewrite
- **Problem:** Display name couldn't be edited (TextField inside a List row had interaction issues). Profile showed UUID instead of email.
- **Fix:** Rewrote ProfileView as a ScrollView with standalone TextField. Added `currentEmail` property to AuthService (read from session). Shows actual email address. Save shows success alert.
- **Impact on future platforms:** AuthService now exposes `currentEmail` from the Supabase session.

### 10. Booking Edit Permissions (Players Can Leave/Add)
- **Problem:** Only the booking creator could modify players. Other players couldn't leave or add someone.
- **Fix:**
  - **RLS policies updated:** `booking_players_delete_self_or_creator` allows any player to remove themselves OR the creator to remove anyone. `booking_players_insert_member` allows any existing player to add new players (not just creator).
  - **BookingDetailView:** Added "Leave Booking" button (non-creator players), "Add Player" button (any player, if < 4 players), and `AddPlayerSheet` modal.
  - **BookingService:** Added `leaveBooking(bookingId:playerId:)` and `addPlayerToBooking(bookingId:playerId:addedBy:)` methods.
- **Constraint enforcement:** The existing `assert_booking_players_constraints` trigger still enforces 2-4 players and creator-must-be-player. Friendly error messages shown if constraint is violated.
- **Impact on future platforms:** RLS policies are in migration `20260405163218_booking_edit_policies.sql`. Any client needs to implement leave/add-player UI. The constraint trigger provides the safety net.

### 11. Launch Screen
- **Problem:** No launch screen configured.
- **Fix:** Added `UILaunchScreen` to Info.plist with `LaunchBackground` (black) color and `LaunchIcon` (200x200 scaled app icon) image assets.
- **Impact:** iOS-only concern. Android uses its own splash screen mechanism.

---

## Required Supabase Extensions Checklist

When setting up a new Supabase project for this app, enable these extensions via Dashboard > Database > Extensions BEFORE pushing migrations:

1. **pg_cron** — Required for notification cron job
2. **pg_net** — Required for cron job to call Edge Functions via HTTP
3. **pgcrypto** — Required for `gen_random_uuid()` (usually auto-enabled)

---

## Current Auth Flow (Updated)

```
App Launch
  → AuthService listens for auth state changes
  → If no session: show LoginView
      → User enters invite code
      → Validate via validate_invite_code RPC (anon-callable)
      → If valid: reveal sign-in options
          → Email/Password sign-in
          → Google Sign-In (native SDK → signInWithIdToken)
          → Apple Sign-In (ASAuthorization → signInWithIdToken)
          → "Forgot Password?" → resetPasswordForEmail
          → "Sign Up" link → SignUpView (no invite code field)
      → If invalid: show error
  → If session exists: show MainView
      → Request push notification permission
      → Save device token to profiles.apns_device_token
```

---

## Current Booking Edit Permissions (Updated)

| Action | Who Can Do It |
|--------|--------------|
| View booking details | Any authenticated user |
| Create booking | Any authenticated user (via `create_booking` RPC) |
| Cancel booking | Creator only |
| Leave booking (remove self) | Any player in the booking (if ≥ 2 players remain) |
| Add player | Any player in the booking (if < 4 players) |
| Remove another player | Creator only |
