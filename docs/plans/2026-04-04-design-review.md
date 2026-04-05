# 214 Pickleball — Design Review & Decisions

Date: 2026-04-04
Status: Approved

## Context

Review of the initial design (BRIEF.md, research docs, schema) to identify gaps, bugs, and finalize architecture decisions before implementation.

## Critical Fix: Booking Creation Atomicity

**Problem:** The `booking_players_size_and_creator_check` constraint trigger is `deferrable initially deferred`, meaning it fires at transaction commit. But PostgREST wraps each API call in its own transaction. Inserting the first player into `booking_players` would trigger the constraint check with a count of 1, raising "must have between 2 and 4 players."

**Fix:** Create a `create_booking` RPC function that performs the entire booking creation (insert booking + insert all players) in a single transaction. The app calls `supabase.rpc("create_booking", ...)` instead of separate inserts.

```sql
create function public.create_booking(
    p_starts_at timestamptz,
    p_player_ids uuid[]
) returns uuid
```

The RPC must:
- Validate player count (2-4) and that the caller is included
- Insert into `bookings`
- Insert all rows into `booking_players`
- Return the new booking ID
- Run as a single transaction so the deferred constraint passes

## Schema Changes Needed

1. **Add `retry_count` to notifications:**
   ```sql
   retry_count smallint not null default 0
   ```
   Edge Function stops retrying after `retry_count >= 3`. Status stays `'failed'` permanently.

2. **Add operating hours constraint to bookings:**
   ```sql
   check (date_part('hour', starts_at at time zone 'America/Toronto') between 5 and 20)
   ```
   Court hours: 5 AM - 9 PM Toronto time (last slot starts at 8 PM, ends 9 PM).

3. **Add invite code to profiles:**
   ```sql
   invite_code text  -- validated during signup flow
   ```
   Or handle via a separate `invite_codes` table if per-org codes are needed later.

4. **Add `create_booking` RPC function** (see critical fix above).

## Architecture Decisions

### Access Control
**Decision:** Invite code at signup.
**Why:** App will be published on the App Store (not just TestFlight), so anyone can download it. Invite code gates registration. Maps cleanly to per-org invite codes when multi-court support is added.

### Notification Delivery
**Decision:** Cron-only (pg_cron every 60 seconds).
**Why:** Simpler than webhook + cron hybrid. Single Edge Function, single trigger path. Up to 60s delay on "instant" notifications is acceptable for a pickleball booking app. Handles both immediate and scheduled (reminder) notifications uniformly.

### Notification Retries
**Decision:** `retry_count` column, max 3 retries, then permanently `'failed'`.
**Why:** Prevents infinite retry loops for permanently failing notifications (e.g., invalid device tokens that return 400 instead of 410).

### Timezone in Notifications
**Decision:** Hardcode court timezone (`America/Toronto`).
**Why:** The court is at a fixed location. Booking times should always display in court time, regardless of the user's profile timezone setting.

### Booking Duration
**Decision:** Fixed 1-hour slots.
**Why:** Matches the brief's "hour-by-hour" design. Simple grid UI. Current unique index on `starts_at` handles conflict detection perfectly. Users book consecutive slots for longer games.

### Operating Hours
**Decision:** 5 AM - 9 PM Toronto time, enforced by DB constraint.
**Why:** Prevents out-of-hours bookings even if someone bypasses the app UI.

### Email Confirmation
**Decision:** Disabled.
**Why:** Invite code is the access gate. Email confirmation adds friction for non-technical users with no real security benefit for a private friend group.

### Distribution
**Decision:** App Store publication (not TestFlight-only).
**Why:** Cleaner install experience. Invite code handles access control.

### Navigation Architecture
**Decision:** Single NavigationStack with NavigationPath.
**Why:** The app has a linear flow (Calendar → Day → Booking). Simpler than TabView. Profile/Settings accessible via toolbar button.

### Realtime + Foreground Refresh
**Decision:** Both Supabase Realtime subscriptions (while active) and re-fetch on `scenePhase` resume.
**Why:** Realtime handles live updates when two users are on the calendar simultaneously. Foreground refresh handles stale data after backgrounding.

### Auth
**Decision:** Email/password + native Google Sign-In SDK → Supabase `signInWithIdToken`. No email confirmation.
**Why:** Native Google sign-in is better UX than browser-based OAuth. ID token exchange is reliable.

### Calendar UI
**Decision:** Native SwiftUI `LazyVGrid` + Foundation `Calendar`.
**Why:** Small user base, simple requirements. No need for HorizonCalendar/FSCalendar dependency.

### Push Notifications
**Decision:** APNs auth key (not TLS cert). Edge Function signs JWT with ES256 via Deno Web Crypto API.
**Why:** Auth key is simpler (no certificate rotation). Web Crypto is built into Deno (no external deps).

### Email Notifications
**Decision:** Resend API called from the same notification Edge Function.
**Why:** One function handles all notification delivery. Resend is simple REST API.

## Future-Proofing Notes

### Android Compatibility
The Supabase backend is platform-agnostic except:
- `profiles.apns_device_token` — add `fcm_token` column when Android ships
- Edge Function push delivery — add FCM branch alongside APNs

No structural backend changes needed for Android.

### Multi-Court / Multi-Org
Not in V1. Current single-court design (unique index on `starts_at`) would need to become `(court_id, starts_at)`. Invite codes map to per-org codes. Schema changes are additive, not destructive.

## Branding

- **App name:** 214 Pickle
- **Domain:** 214-pickle.com (purchased for potential future website)
- **Color scheme** (from Kris's 214 company logo):
  - Background: Black
  - Text: White
  - Accent: Bright lime green (~`#7AC143`, exact value TBD from logo)
- **Logo:** Marcus creating a unique logo incorporating pickleball elements, distinct from Kris's 214 company mark. Must be original for App Store.
- **Design direction:** Dark-mode primary. Green for interactive elements, CTAs, booking indicators. Clean and bold.

## Pre-Implementation Tasks

Before writing code:
1. ~~**Branding decisions**~~ — Resolved: "214 Pickle", black/white/green. Logo in progress.
2. **Apple Developer account** — Team ID, APNs key, bundle ID registration (e.g., `com.214-pickle`)
3. **Google Cloud Console** — OAuth client IDs (iOS + Web)
4. **Supabase project** — Create project, note project ref and keys
5. **Resend account** — API key, verified sender domain/email
6. **Schema updates** — Apply the fixes listed above to the migration
7. **App icon** — Marcus to finalize with AI-generated pickleball variant of 214 mark
