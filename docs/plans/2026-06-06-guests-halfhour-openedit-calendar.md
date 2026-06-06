# Guests + Half-Hour Slots + Open Editing + Calendar Invites — Implementation Plan

> **For Claude:** Execute task-by-task. Verify each layer (DB via local Supabase SQL harness, edge fn via deno, iOS via xcodebuild) before moving on. Get Codex review before deploying.

**Goal:** Ship a 214 Pickle update with four features: (1) guest players in bookings, (2) 30-minute slot granularity, (3) open booking editing by any user, (4) `.ics` calendar invites in notification emails. Deploy backend to the linked Supabase project and upload an iOS build to TestFlight.

**Architecture:** Backend changes ship as new Supabase migrations + an Edge Function update; iOS changes ship as a new binary. All four features are coordinated across DB ↔ iOS.

**Tech Stack:** Supabase (Postgres + RLS + triggers + Edge Functions/Deno + Resend), Swift/SwiftUI, fastlane/Xcode.

---

## Context discovered (current state — important, CLAUDE.md is partly stale)

- **Bookings are ALREADY multi-hour (1–4h)**, not fixed 1-hour. Live RPC is the 3-arg `create_booking(p_starts_at, p_ends_at, p_player_ids uuid[])` in `20260405203503_multi_hour_bookings.sql`.
- **Open editing is HALF-DONE at the DB layer** (`20260405163218_booking_edit_policies.sql`): any member can add players; you can remove yourself; creator can remove anyone. The bookings ROW (cancel) is still creator-only via `enforce_booking_update_rules` + `bookings_update_creator`.
- `booking_players`: `player_id uuid NOT NULL REFERENCES profiles(id)`, PK `(booking_id, player_id)`. No guest concept.
- On-the-hour is enforced in 4 places: table CHECK `date_part('minute', starts_at)=0…` (initial schema, **unnamed, never dropped**), `bookings_ends_at_on_hour` CHECK, and two minute-checks inside `create_booking`.
- Notification emails are built in `supabase/functions/send-notifications/index.ts` → `sendEmail()`, currently `html: "<p>${body}</p>"`, **no attachments, and it never fetches booking times**.
- Linked Supabase project ref: `ttdeyiriqminwguozbal`. iOS version: `CFBundleShortVersionString=1.0`, `CFBundleVersion=1` (in `Info.plist`, since `GENERATE_INFOPLIST_FILE=NO`).
- Court name lives on `court_codes.court_name` (default `'214 Pickle'`); bookings have no court link → `.ics` LOCATION uses a constant `"214 Pickle"`.

---

## Design decisions (with rationale)

### Feature 1 — Guests
- **Data model:** extend `booking_players` (NOT a separate table — single source for the 2–4 count).
  - Add surrogate `id uuid primary key default gen_random_uuid()` (replace PK `(booking_id, player_id)`).
  - Make `player_id` **nullable**; add `guest_name text`.
  - CHECK: exactly one of (`player_id`, `guest_name`) is set: `(player_id is not null and guest_name is null) or (player_id is null and guest_name is not null)`.
  - Partial unique index `(booking_id, player_id) where player_id is not null` keeps the no-duplicate-real-player guarantee. Guests may duplicate.
  - Unnamed guest → stored as `guest_name = 'Guest'` (RPC/insert normalizes empty/blank to `'Guest'`, capped at 50 chars). Avoids null+null violating the CHECK and keeps display trivial.
- **Creator must still be a real user** (the deferred `assert_booking_players_constraints` checks `created_by` is among real `player_id`s — guests can never satisfy it, which is correct).
- **No cap on guests**, but total participants still ≤ 4 (court limit). Up to 3 guests (creator + 3 guests).
- **Notifications:** guests get none (no profile/email). The enqueue trigger early-returns when `player_id is null`.
- **Display:** real users look exactly as today. Guests show a distinct avatar glyph + a `Guest` badge (reusing `Theme.surfaceLight`/`Theme.textSecondary`, like the `Organizer`/`You` badges). Name = guest_name (e.g. "Dave") with the `Guest` badge → reads as "Dave · Guest".

### Feature 2 — 30-minute slots
- Relax all four on-the-hour gates to allow `minute in (0,30)`, `second = 0`.
- Keep 4-hour max duration and 5 AM–9 PM operating window. Add an explicit **end-by-9 PM** check in the RPC (robust against the UI being bypassed; computed as 21:00 Toronto on the start's day, DST/midnight-safe).
- Slots: 5:00, 5:30, … 20:30 (32 rows). Latest start 8:30 PM → ends 9:00 PM.
- iOS: `TimeSlot` keyed on exact start `Date` (drop `hour: Int`); matching by timestamp range, not hour component. End-time picker and duration math step in 30-min increments with friendly labels ("30 min", "1 hr", "1 hr 30 min", …).

### Feature 3 — Open editing
- **Keep the natural guards** (deferred constraint: creator must remain; 2–4 count) — these prevent full hijack / emptying without extra logic. Matches "don't over-complicate."
- **RLS INSERT** (`booking_players_insert_open`): any authenticated user may add **themselves** (self-join, `player_id = auth.uid()`), and any **member** may add other real players or guests. Booking must be active + future; `added_by = auth.uid()`.
- **RLS DELETE** (`booking_players_delete_member`): any **member** may remove any participant (incl. guests); you may always remove yourself. Active bookings. (Removing the creator fails the deferred constraint; removing below 2 fails the count — clean natural guards.)
- **Cancel stays creator-only** (the user asked to open *player editing*, not destruction of the whole booking). No change to `enforce_booking_update_rules`.
- iOS: non-members see "Join this booking"; members see "Add Player"/"Add Guest" and a remove (✕) on non-organizer rows.

### Feature 4 — Calendar invite
- Generate an **iCalendar (`.ics`) VEVENT**, attach to the Resend email as `invite.ics` with `content_type: "text/calendar; charset=utf-8; method=PUBLISH"`.
  - `METHOD:PUBLISH` (an event to add, not an RSVP request → no confusing Accept/Decline). Apple Mail & Gmail add it natively.
  - Stable `UID = <booking_id>@214-pickle.com`. DTSTART/DTEND in UTC (`…Z`). SUMMARY "Pickleball @ 214 Pickle", LOCATION "214 Pickle", DESCRIPTION lists participants. RFC-5545 line folding + value escaping.
  - Booking-cancelled emails attach a `METHOD:CANCEL` ics (same UID, `STATUS:CANCELLED`, `SEQUENCE:1`) so a previously-added event is removed automatically.
- Also embed explicit **"Add to Google Calendar" / "Add to Outlook"** buttons in the email body (belt-and-suspenders; the original requester uses Outlook). Apple/other → the attached `invite.ics`.
- Replace the bare `<p>${body}</p>` with a clean branded HTML template. **HTML-escape** the body (guest names are now user-supplied and flow into emails).
- Worker change: in the email branch, fetch the booking (`starts_at, ends_at, created_by, status`) + participant names so the ics/HTML can be built. Reminder emails are push-only today; only `booking_created` (PUBLISH) and `booking_cancelled` (CANCEL) carry an ics.

---

## Migrations (apply order by timestamp)

### `supabase/migrations/20260606120000_halfhour_slot_constraints.sql`
- Drop the unnamed initial-schema `starts_at` minute=0 CHECK (matched via `pg_get_constraintdef` `like '%minute%starts_at%second%starts_at%'`).
- Drop `bookings_ends_at_on_hour`.
- Add `bookings_starts_on_half_hour` (`minute in (0,30) and second=0`) and `bookings_ends_on_half_hour`.
- Keep `bookings_ends_after_starts`, `bookings_max_duration`, the 5–20 start-hour CHECK.

### `supabase/migrations/20260606120100_guest_players_and_booking_rpc.sql`
- `booking_players`: drop PK, add `id uuid pk default gen_random_uuid()`, `alter player_id drop not null`, add `guest_name text`, add the one-of CHECK, add partial unique index on `(booking_id, player_id)`.
- Update `enqueue_booking_notifications_on_player_insert`: early `return new` when `new.player_id is null`.
- `drop function create_booking(timestamptz,timestamptz,uuid[])`; create final `create_booking(p_starts_at, p_ends_at, p_player_ids uuid[], p_guest_names text[] default '{}')`:
  - total = real + guests, 2–4; caller ∈ p_player_ids; distinct real ids; not past; start hour 5–20; start/end minute in (0,30) sec 0; end>start; ≤4h; **end ≤ 21:00 Toronto same day**; overlap check (unchanged interval logic).
  - insert booking; insert real players; insert guests (`player_id null`, normalized `guest_name`, `added_by=caller`).
  - grants to authenticated.
- (Deferred `assert_booking_players_constraints` needs **no change** — `count(*)` already counts guests; creator-present already requires a real row.)

### `supabase/migrations/20260606120200_open_editing_policies.sql`
- Drop `booking_players_insert_member` → add `booking_players_insert_open` (self-join OR member-adds; active+future).
- Drop `booking_players_delete_self_or_creator` → add `booking_players_delete_member` (self OR member; active).

---

## Edge function

`supabase/functions/send-notifications/index.ts`:
- Add `escapeHtml`, `icsEscape`, `foldICSLine`, `formatICSDate` (UTC `YYYYMMDDTHHMMSSZ`), `buildICS({uid, method, sequence, status, start, end, summary, location, description})`.
- Add `buildEmailHtml({title, body, addToCalendar})` → branded template with Google/Outlook buttons (omitted on cancel).
- `sendEmail(to, subject, body, opts?)` grows an optional `{ ics?: {filename, content, method}, addToCalendar? }`; when present, include `attachments: [{ filename, content: base64(ics), content_type: "text/calendar; charset=utf-8; method=…" }]` and the calendar buttons.
- In the email branch of the worker loop: if `notif.booking_id` and type ∈ {booking_created, booking_cancelled}, fetch booking + participants, build ics (PUBLISH/CANCEL) and add-to-calendar links, pass to `sendEmail`.

## iOS

- `Models/Booking.swift`: `BookingParticipant` (rowId, userId?, displayName, avatarUrl, isGuest); `BookingWithPlayers.players: [BookingParticipant]`; `BookingPlayer` decode gains `id`, optional `playerId`, `guestName`; add `BookingPlayerInsert` (real) — guests added via a new RPC param or a guest insert struct; `TimeSlot` keyed on exact start `Date` (drop `hour`).
- `Services/BookingService.swift`: rewrite `timeSlotsForDay` (30-min stride, range matching), `availableEndTimes(from:)` (30-min steps, end-by-9PM, ≤4h, next-booking cap), `createBooking(startsAt:endsAt:playerIds:guestNames:)`, `addGuestToBooking`, `removeParticipant(rowId:)`, build `[BookingParticipant]` in `fetchBookingsForDay`.
- `Views/Booking/BookingCreateView.swift`: guest entries (`[GuestEntry]`), total counter, "Add Guest", guest rows with optional-name TextField; submit passes guestNames; half-hour duration labels.
- `Views/Booking/BookingDetailView.swift`: render participants (guest glyph + badge); "Join this booking" for non-members; "Add Player"/"Add Guest" for members; remove ✕ on non-organizer rows for members; friendly constraint errors; AddPlayerSheet supports adding a guest.
- `Views/Schedule/TimeSlotRow.swift`: `isBookingStart` by timestamp; 30-min duration label; participant names (guests shown as "Dave (guest)" inline).
- Bump `Info.plist`: `CFBundleShortVersionString` → `1.1`, `CFBundleVersion` → `2`.

## Verification
1. `supabase db reset` (local) applies all migrations; run `scripts/test_booking_rules.sql` harness covering: 30-min create, guest create (incl. all-3-guests), self-join, member add/remove, can't remove creator, can't drop below 2, reject :15, reject end>9PM, overlap reject, notifications skip guests.
2. `deno test` on the ics builder (RFC 5545 shape, escaping, folding, UTC, PUBLISH/CANCEL).
3. `xcodebuild build` for an iOS Simulator destination — must compile clean.
4. `codex-review` on migrations + edge fn + Swift until APPROVE.
5. Deploy: `supabase db push`, `supabase functions deploy send-notifications`; archive + upload to TestFlight.

## Risks
- **Prod data + PK swap:** migration must be safe on populated `booking_players`. Surrogate-id add + PK swap preserves rows; existing rows get generated ids. Tested locally with seeded active bookings first.
- **Direct booking insert bypasses RPC overlap check** (pre-existing via `bookings_insert_own`): out of scope; app only uses the RPC.
- **Backend/iOS coordination:** open-editing RLS + guest schema must be live before the new binary is used. Deploy backend first, then ship build.
