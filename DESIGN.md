# 214 Pickleball - Design Document

## 1. Architecture Overview

### 1.1 System Architecture (SwiftUI + Supabase)
```text
+--------------------------------------------------------------+
|                        iOS App (SwiftUI)                     |
|--------------------------------------------------------------|
| Views: MonthCalendar, DaySchedule, BookingCreate, Profile    |
| ViewModels: Auth, Calendar, DaySchedule, Booking, Profile    |
| Services: SupabaseAuthService, BookingService, Notification  |
| Local Cache: lightweight persisted cache (recent days/bookings)
+---------------------------+----------------------------------+
                            |
                            | HTTPS + WebSocket (Realtime)
                            v
+--------------------------------------------------------------+
|                         Supabase Backend                      |
|--------------------------------------------------------------|
| Auth: email/password + Google OAuth (PKCE)                   |
| Postgres: profiles, bookings, booking_players, notifications |
| RLS: per-table policies                                      |
| Realtime: postgres changes on bookings + booking_players     |
| Edge Functions: notification dispatcher (push + email)       |
+------------------------+----------------------+--------------+
                         |                      |
                         v                      v
                 Apple Push Notification     Email Provider
                 service (APNs)              (Resend/SendGrid)
```

### 1.2 iOS App Layering
- `View`: rendering and user interaction.
- `ViewModel`: screen state, async actions, input validation.
- `Repository/Service`: Supabase queries, realtime subscriptions, mapping DTOs to app models.
- `Domain Model`: `Profile`, `Booking`, `BookingPlayer`, `NotificationJob`.

### 1.3 Key Design Decisions
- Native SwiftUI month grid (`LazyVGrid`) for V1 simplicity and full control.
- Server-authoritative booking state (Postgres + RLS), not peer-to-peer state.
- Queue-based notifications in DB so push/email delivery is retryable and observable.
- Realtime subscriptions keep all users' calendars synchronized without manual refresh.

## 2. Data Model
The canonical schema is defined in [docs/supabase-schema-design.md](docs/supabase-schema-design.md).

### 2.1 Entities
- `profiles`: user profile and notification preferences (1:1 with `auth.users`).
- `bookings`: one row per court booking slot.
- `booking_players`: many-to-many join between bookings and players.
- `notifications`: queued and delivered notification events.

### 2.2 Core Constraints
- One active booking per hour slot (`UNIQUE` partial index on `bookings.starts_at`).
- Booking must include 2-4 players.
- Booking creator must be included in `booking_players`.
- Only booking creator can cancel their own booking.

## 3. Authentication Flow

### 3.1 Signup (Email/Password)
1. User enters name, email, password.
2. App calls `supabase.auth.signUp(...)`.
3. Supabase creates `auth.users` row.
4. DB trigger auto-creates `profiles` row.
5. App routes to month calendar after valid session (or after email confirmation if enabled).

### 3.2 Login (Email/Password)
1. User enters email/password.
2. App calls `supabase.auth.signIn(...)`.
3. On success, load profile + current month bookings.
4. Restore nav state to month view.

### 3.3 Google OAuth (Supabase)
1. User taps `Continue with Google`.
2. App launches Supabase OAuth flow (`signInWithOAuth(provider: .google)` with PKCE).
3. Browser/auth session returns Supabase session.
4. If first login, `profiles` row is auto-provisioned by trigger.
5. App lands on month calendar.

### 3.4 Session Management
- On launch: check cached session and refresh if needed.
- On auth state changes: reset app state when signed out or session invalid.
- Service role keys never ship in the app binary.

## 4. UI Specifications (4 Views)

## 4.1 Month Calendar (Main Landing)
### Purpose
Global overview of bookings by day; primary entry point.

### Layout
- Header: month/year label, previous/next month buttons.
- 7-column weekday row.
- Month grid cells (5-6 rows) with date number.
- Day indicator dot/badge if one or more bookings exist.
- Toolbar: profile/settings button.

### Interactions
- Past days: visually muted and non-interactive.
- Today/future day tap: navigate to Day Schedule for selected date.
- Swipe or buttons to change month.

### States
- Loading: skeleton cells.
- Empty: no dots on any day.
- Error: inline retry banner.

## 4.2 Day Schedule (Hour-by-Hour)
### Purpose
Show availability and existing bookings for selected day.

### Layout
- Header with selected date.
- Scrollable list of hourly slots (7:00 to 21:00 local).
- Slot row includes:
  - Time label
  - Status badge (`Available`, `Booked`, `Your Booking`)
  - Player names for booked slots

### Interactions
- Tap `Available` slot -> navigate to Booking Create with preselected time.
- Tap `Your Booking` -> open booking detail action sheet (`Cancel booking`).
- Tap `Booked` by others -> read-only participant view.

### States
- Loading slots.
- No slots available (all booked).
- Error with pull-to-refresh retry.

## 4.3 Booking Create (Select Time + Players)
### Purpose
Create a booking in one flow.

### Layout
- Read-only selected date/time summary.
- Player picker list (multi-select) from app user directory.
- Current user shown as always included.
- Footer summary: total players count (`2-4 required`).
- Primary CTA: `Confirm Booking`.

### Validation
- Must have total 2-4 players.
- Cannot submit past slot.
- Slot must still be free at commit time.

### Result
- On success: dismiss to Day Schedule with optimistic confirmation.
- On slot conflict: show conflict message and refresh day data.

## 4.4 Profile / Settings
### Purpose
User identity and notification preferences.

### Layout
- Profile card: display name, avatar placeholder.
- Notification toggles:
  - Push notifications enabled
  - Email notifications enabled
- Account actions: sign out.

### Interactions
- Save profile updates inline.
- Register/update APNs device token when push is enabled.

## 5. Navigation Flow

```text
Auth Gate
  -> Month Calendar
      -> Day Schedule (selected date)
          -> Booking Create (selected slot)
              -> Back to Day Schedule (after create)
      -> Profile/Settings (from toolbar)

Global:
- Sign out from Profile returns to Auth Gate.
- Booking cancellation from Day Schedule refreshes Day + Month views.
```

Navigation style: `NavigationStack` with typed route enum (`month`, `day(date)`, `bookingCreate(date, hour)`, `profile`).

## 6. Notification Strategy

### 6.1 Push Notifications (APNs)
- iOS app requests remote notification permission after onboarding.
- APNs token is captured and stored in `profiles.apns_device_token`.
- DB triggers create `notifications` queue rows (`pending`) for:
  - player added to booking
  - booking cancelled
  - booking reminder (1 hour before)
- Edge Function worker sends APNs payload and updates status (`sent`/`failed`).

### 6.2 Email Notifications (Edge Functions)
- Same queue table drives email channel entries.
- Edge Function uses Resend or SendGrid API key via Supabase secrets.
- Email events:
  - included in new booking
  - booking cancelled
- Delivery metadata stored back on `notifications` row.

## 7. Realtime Sync Approach
- Subscribe to `bookings` and `booking_players` via Supabase Realtime Postgres Changes.
- On `insert/update/delete` events:
  - invalidate month day-indicator cache for affected date
  - reload day schedule for affected date if on-screen
- Apply optimistic UI for create/cancel, then reconcile with realtime/server response.
- RLS keeps subscriptions limited to rows visible to authenticated users.

## 8. Error Handling Patterns
- Central `AppError` enum (`network`, `auth`, `validation`, `conflict`, `unknown`).
- Map PostgREST conflict (`23505` unique violation on slot) to user-friendly message: "That slot was just taken."
- Non-blocking banner/toast for transient failures; blocking alerts for destructive action failures.
- Retry policies:
  - idempotent reads: automatic retry with exponential backoff
  - writes: explicit user retry to avoid duplicate intents
- Structured logging for auth, booking writes, realtime reconnects, notification send failures.

## 9. Offline Behavior
- App caches recent month/day booking data and profile in local storage.
- Offline reads:
  - Month and day views show last-synced data with "Offline" indicator.
- Offline writes:
  - Create/cancel booking actions are disabled when offline (V1 simplicity and consistency).
  - UI shows actionable message: "Reconnect to update bookings."
- Reconnect behavior:
  - refresh month/day data immediately
  - restart realtime subscriptions
  - clear stale error banners

## 10. Security and Privacy
- RLS enforced on all core tables.
- Users can only modify their own profile and their own bookings.
- Notification queue rows are only readable by recipient.
- App includes anon key only; service role key remains server-side in Edge Functions.
