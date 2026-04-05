# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**214 Pickle** is a private court scheduling iOS app for Kris's pickleball group (~10-20 users, max 50). Single court; users book 1-hour time slots and invite other players. iOS first, App Store publication. Android planned for later sharing the same Supabase backend.

## Tech Stack

- **Frontend:** Swift / SwiftUI (iOS 13+, Xcode 15.3+, Swift 5.10+)
- **Backend:** Supabase (auth, Postgres DB, realtime subscriptions, Edge Functions)
- **Package manager:** Swift Package Manager (SPM)
- **Supabase SDK:** `supabase-swift` v2.0+ via SPM
- **Google Sign-In SDK:** `GoogleSignIn-iOS` v9.0.0 + `GoogleSignInSwift` via SPM
- **Distribution:** App Store (TestFlight for beta)

## Architecture Decisions (from research docs)

- **Auth:** Email/password + Google OAuth + Apple Sign-In via Supabase. Both social sign-ins use native `signInWithIdToken` (not browser OAuth). Apple Sign-In requires nonce (SHA-256 hash to Apple, raw nonce to Supabase). Apple only provides user's full name on first sign-in — must capture immediately. PKCE flow enabled.
- **Calendar:** Native SwiftUI `LazyVGrid` + Foundation `Calendar` APIs for month view (no third-party calendar library in V1). HorizonCalendar is the fallback if complexity grows.
- **Realtime:** Supabase Realtime Postgres Changes for live booking updates. Tables must be in `supabase_realtime` publication with proper RLS.
- **Push notifications:** APNs auth key (not TLS cert). iOS app registers device token -> `profiles.apns_device_token` column -> DB trigger -> Edge Function -> APNs HTTP/2 API.
- **Email notifications:** Supabase Edge Function + Resend API for booking events. Supabase built-in templates for auth emails only.
- **Email sending:** Resend API via `send.214-pickle.com` subdomain. From address: `noreply@send.214-pickle.com`.
- **Security:** Anon key (publishable key) in app binary is fine; never embed service role key (secret key) in iOS. All data access through RLS policies.

## App Structure (4 Views)

1. **Month Calendar** - Landing screen. Grid of days with booking indicators. Past days greyed/disabled.
2. **Day Schedule** - Hour-by-hour slots (5 AM - 9 PM). Shows available/booked/your-booking.
3. **Booking Detail/Create** - Select slot, pick 1-3 other players (2-4 total), confirm.
4. **Profile/Settings** - Account info, notification preferences.

## Database Schema

4 tables: `profiles`, `bookings`, `booking_players`, `notifications`. Full migration in `docs/supabase-schema-design.md`.

- **profiles** extends `auth.users` (auto-created via `handle_new_user` trigger). Stores display name, avatar, timezone (`America/Toronto` default), notification prefs, APNs token.
- **bookings** are 1-hour slots enforced by check constraints. Only `active` -> `cancelled` transition allowed. Unique partial index prevents double-booking a slot. Only creator can cancel (enforced by `enforce_booking_update_rules` trigger).
- **booking_players** is a join table (2-4 players per booking, creator must be included — enforced by deferred constraint trigger). Inserting players auto-enqueues notifications.
- **notifications** is a queue table. DB triggers write `pending` rows on booking create/cancel; Edge Function worker polls and delivers via APNs or email, then updates status.

RLS: profiles are private (own row only), bookings/players are read-visible to all authenticated users, notifications are private. Player list is exposed via `list_players()` security definer function.

## Branding

- **Name:** 214 Pickle | **Domain:** 214-pickle.com
- **Colors:** Black background, white text, bright lime green accent (~`#7AC143`)
- **Design:** Dark-mode primary. Green for interactive elements, CTAs, booking indicators.

## Key Design Decisions (from design review)

- **Booking creation:** Must use `create_booking` RPC function (PostgREST can't do multi-table transactions with deferred constraints)
- **Access control:** Invite code at signup (App Store is public, need a gate)
- **Notification delivery:** Cron-only (pg_cron every 60s), single Edge Function
- **Notification retries:** `retry_count` column, max 3 retries then permanently `'failed'`
- **Operating hours:** 5 AM - 9 PM Toronto time, enforced by DB constraint
- **Timezone:** Hardcoded to court location (`America/Toronto`) in notification text
- **Email confirmation:** Disabled (invite code is the access gate)
- **Navigation:** Single NavigationStack with NavigationPath, auth guard at root
- **Realtime:** Supabase Realtime while active + re-fetch on foreground resume

See `docs/plans/2026-04-04-design-review.md` for full rationale.

## Key Constraints

- Single court only (no multi-court logic in V1; planned for future)
- Users can only cancel their own bookings, not edit others'
- No recurring bookings, payments, or waitlist in V1
- Fixed 1-hour slots (book consecutive slots for longer games)

## Research Docs

The `docs/` directory contains verified research with source citations:

**iOS App:**
- `supabase-ios.md` - supabase-swift SDK patterns (auth, queries, realtime, push)
- `google-signin-ios.md` - Google Sign-In SDK setup, ID token extraction, Supabase token exchange
- `swiftui-calendar.md` - Month grid implementation with LazyVGrid
- `swiftui-navigation.md` - NavigationStack patterns, NavigationPath, OAuth URL scheme config
- `apple-push-notifications.md` - Client-side APNs setup, Xcode config, device token registration

**Supabase Backend:**
- `supabase-schema-design.md` - Full SQL migration, RLS policies, triggers, indexes
- `supabase-edge-functions.md` - Edge Functions, DB webhooks, pg_cron scheduling, secrets
- `supabase-email-notifications.md` - Edge Function + Resend email pattern
- `apns-server-sending.md` - Server-side APNs from Edge Functions (JWT/ES256, HTTP/2, Deno Web Crypto)
- `supabase-cli-local-dev.md` - CLI installation, local dev stack, migrations, deployment workflow

**Distribution:**
- `ios-app-distribution.md` - TestFlight and App Store distribution steps

**Design:**
- `plans/2026-04-04-design-review.md` - All architecture decisions with rationale
