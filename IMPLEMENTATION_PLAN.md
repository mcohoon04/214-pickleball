# 214 Pickleball - Implementation Plan

## Delivery Assumptions
- Platform: iOS only (SwiftUI).
- Backend: Supabase (Auth, Postgres, Realtime, Edge Functions).
- User volume: private group, <50 users.
- Apple Developer Account: **already set up** ($99/year requirement satisfied).
- Estimates assume one experienced iOS engineer and include development + basic QA per phase.

## Phase 1 - Project Setup + Supabase Setup + Auth

### Estimated effort
- **12-16 hours**

### Dependencies
- None

### Tasks
- Create Xcode project with bundle IDs for Debug/Release.
- Add `supabase-swift` via SPM and configure environment loading.
- Create Supabase project and baseline SQL migration from `docs/supabase-schema-design.md`.
- Configure Supabase Auth providers:
  - Email/password
  - Google OAuth (redirect URLs, PKCE flow)
- Implement auth screens and auth session bootstrap.
- Implement `profiles` auto-provisioning trigger verification.

### Acceptance criteria
- User can sign up with email/password and sign in successfully.
- User can sign in with Google OAuth and return to app session.
- First login creates corresponding `profiles` row.
- Sign out returns to auth gate and clears authenticated state.

## Phase 2 - Month Calendar View + Navigation

### Estimated effort
- **10-14 hours**

### Dependencies
- Phase 1 complete (auth/session and Supabase client setup)

### Tasks
- Build Month Calendar screen as default post-login landing view.
- Implement month math (leading/trailing cells, weekday headers).
- Grey out past days and disable interaction.
- Add day-level booking indicators from `bookings` data.
- Add navigation to Day Schedule with selected date payload.
- Add toolbar route to Profile/Settings.

### Acceptance criteria
- Current month renders correctly on all supported iPhone sizes.
- Past dates cannot be tapped.
- Today/future dates navigate to Day Schedule.
- Booking indicator dots reflect backend data.

## Phase 3 - Day Schedule View (Hour-by-Hour Slots)

### Estimated effort
- **10-14 hours**

### Dependencies
- Phase 2 complete

### Tasks
- Build day schedule list for configured time range (7:00-21:00 local).
- Join `bookings + booking_players + profiles` data for slot display.
- Render slot states: `Available`, `Booked`, `Your Booking`.
- Add pull-to-refresh and loading/error states.
- Add slot tap handling:
  - Available -> Booking Create
  - Your Booking -> cancellation action
  - Others' booking -> read-only details

### Acceptance criteria
- All hourly slots render in correct order and timezone.
- Slot status is accurate and updates after refresh.
- Navigation to Booking Create from available slot works.
- Cancellation action is only offered for current user's booking.

## Phase 4 - Booking Creation + Player Selection

### Estimated effort
- **14-18 hours**

### Dependencies
- Phase 3 complete

### Tasks
- Build Booking Create view with preselected date/time.
- Fetch user list via `list_players()` RPC or profile directory endpoint.
- Implement multi-select player picker (creator always included).
- Validate 2-4 total players before enabling submit.
- Implement atomic booking create flow:
  - insert into `bookings`
  - insert selected rows in `booking_players`
- Handle slot race conflicts (`23505`) with clear UX message.

### Acceptance criteria
- User can create booking with valid participant count.
- Booking appears in Day and Month views immediately after create.
- Conflict is handled gracefully when slot is already taken.
- User cannot create bookings in past slots.

## Phase 5 - Realtime Sync (Live Calendar Updates)

### Estimated effort
- **8-12 hours**

### Dependencies
- Phase 4 complete

### Tasks
- Enable Realtime subscriptions for `bookings` and `booking_players`.
- Subscribe on app foreground and reconnect on network/session changes.
- Invalidate and reload month/day state on insert/update/delete events.
- Add de-duplication/reconciliation between optimistic updates and realtime callbacks.
- Add telemetry for subscription lifecycle and reconnect failures.

### Acceptance criteria
- Two devices logged into different users see booking create/cancel updates within seconds.
- No manual refresh required for shared calendar consistency.
- Reconnect recovers realtime stream after temporary disconnect.

## Phase 6 - Push Notifications (APNs + Supabase)

### Estimated effort
- **12-16 hours**

### Dependencies
- Phase 1, 4, and 5 complete

### Tasks
- Configure Apple Push capability in App ID + Xcode target.
- Implement APNs permission request and device token registration.
- Store/update APNs token in `profiles.apns_device_token`.
- Implement Supabase Edge Function worker for push delivery from `notifications` queue.
- Add secure secret management for APNs credentials.
- Update app to deep-link/open relevant booking context from push tap.

### Acceptance criteria
- Device receives push when added to a booking.
- Device receives push for booking cancellation.
- Device receives reminder push about one hour before booking.
- Failed push attempts are reflected in notification row status.

## Phase 7 - Email Notifications (Edge Functions + Provider)

### Estimated effort
- **8-12 hours**

### Dependencies
- Phase 6 complete (notification queue pipeline in place)

### Tasks
- Integrate Resend or SendGrid in existing Edge Function flow.
- Add HTML/text email templates for booking created/cancelled events.
- Map `notifications` email-channel rows to provider payloads.
- Persist provider response IDs and delivery status.
- Add retry handling for transient provider failures.

### Acceptance criteria
- Included players receive booking-created email.
- Included players receive cancellation email.
- Provider failures are logged and visible in notification status.

## Phase 8 - Polish, Testing, and TestFlight Distribution

### Estimated effort
- **14-20 hours**

### Dependencies
- Phases 1-7 complete

### Tasks
- UI polish pass (spacing, typography, accessibility labels, Dynamic Type checks).
- Add unit tests for booking/business rules and view model logic.
- Add integration tests for auth and booking happy path.
- Perform manual QA matrix across at least 2 iOS versions and multiple device sizes.
- Configure App Store Connect metadata for TestFlight external group.
- Archive, upload, and distribute beta build via TestFlight.

### Acceptance criteria
- Core flows pass QA: auth, month/day navigation, booking create/cancel, realtime updates, push/email notifications.
- No Sev-1/Sev-2 defects open for beta.
- External testers can install and use build through TestFlight invite.

## Recommended Xcode Project Structure

```text
214Pickleball/
  App/
    PickleballApp.swift
    AppRouter.swift
    AppEnvironment.swift
  Core/
    Models/
      Profile.swift
      Booking.swift
      BookingPlayer.swift
      NotificationItem.swift
    Networking/
      SupabaseClientProvider.swift
      APIError.swift
    Utilities/
      DateFormatting.swift
      Logger.swift
      ReachabilityMonitor.swift
  Features/
    Auth/
      AuthView.swift
      AuthViewModel.swift
      AuthService.swift
    Calendar/
      MonthCalendarView.swift
      MonthCalendarViewModel.swift
      MonthGridBuilder.swift
    DaySchedule/
      DayScheduleView.swift
      DayScheduleViewModel.swift
      SlotRowView.swift
    BookingCreate/
      BookingCreateView.swift
      BookingCreateViewModel.swift
      PlayerPickerView.swift
    Profile/
      ProfileView.swift
      ProfileViewModel.swift
  Services/
    BookingService.swift
    ProfileService.swift
    RealtimeService.swift
    NotificationService.swift
  Resources/
    Assets.xcassets
    Config/
      Debug.xcconfig
      Release.xcconfig
  Tests/
    Unit/
    Integration/
```

## Naming Conventions
- Views: `FeatureNameView`.
- View models: `FeatureNameViewModel`.
- Services: `DomainService` (e.g., `BookingService`).
- Async methods use verb-first names (`fetchMonthBookings`, `createBooking`, `cancelBooking`).
- Route enum cases use lower camel case (`daySchedule(date:)`).

## Estimated Total
- **88-122 hours** total (depending on QA depth and notification edge-case handling).
