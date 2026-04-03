# 214 Pickleball — Product Brief

## Context
Private pickleball court owned by Kris. He and his buddies need a way to book court times. Currently no system — need a simple iOS app.

## Users
- Kris and approximately 10-20 friends/buddies
- All iOS users
- Non-technical users — app must be dead simple

## Core Features

### Authentication
- Create account (email/password)
- Google OAuth option
- Simple onboarding — name, email, profile

### Shared Calendar (Month View)
- Default landing screen after login
- Month view calendar grid
- Past days are greyed out / non-interactive
- Today and future days are clickable
- Visual indicators showing which days have bookings

### Day View (Hour-by-Hour Schedule)
- Tap a day → shows hourly time slots (e.g., 7 AM to 9 PM)
- Each slot shows: available, booked (with player names), or your booking
- Tap an available slot to book

### Booking Flow
- Select a time slot
- Select 1, 2, or 3 other players from the user list to play with (total 2-4 players)
- Confirm booking
- Booking appears immediately for all users

### Notifications
- Push notification when someone books a slot you're in
- Push notification for booking reminders (e.g., 1 hour before)
- Email notification for new bookings you're included in
- Push notification if a booking you're in gets cancelled

### Booking Management
- View your upcoming bookings
- Cancel your own bookings
- Cannot edit someone else's booking

## Views (4 total)
1. **Month Calendar** — main landing, overview of the month
2. **Day Schedule** — hour-by-hour for selected day
3. **Booking Detail / Create** — book a slot, select players
4. **Profile / Settings** — account info, notification preferences

## Technical Constraints
- iOS only (no Android needed for now)
- Small user base (< 50 users max)
- Single court (no multi-court complexity)
- Backend needs to be simple and low-maintenance
- Supabase preferred for speed (auth, DB, realtime, push) unless there's a strong reason for custom

## Non-Goals (V1)
- No payments / billing
- No recurring bookings
- No waitlist
- No Android
- No web version
- No multi-court support
