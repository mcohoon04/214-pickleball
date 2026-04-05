# 214 Pickle — App Store Submission Guide

Complete field-by-field guide for App Store Connect. Fill in every field exactly as listed.

---

## 1. Deploy Website First

Upload the `website/` directory to 214-pickle.com. The site has 4 pages:
- `index.html` → `https://214-pickle.com`
- `support.html` → `https://214-pickle.com/support`
- `privacy.html` → `https://214-pickle.com/privacy`
- `terms.html` → `https://214-pickle.com/terms`
- `icon.png` → `https://214-pickle.com/icon.png`

**Hosting options:** Cloudflare Pages (free, already using Cloudflare DNS), Vercel, or Netlify. Cloudflare Pages is simplest since DNS is already there.

### Cloudflare Pages Setup:
1. Go to Cloudflare Dashboard → Pages → Create a project
2. Connect to your git repo OR direct upload the `website/` folder
3. Set custom domain: `214-pickle.com`
4. Verify pages load at the URLs above

**You must have working URLs before submitting to Apple.**

---

## 2. App Store Connect — App Information

### App Name
```
214 Pickle
```

### Subtitle (30 chars max)
```
Private Court Scheduling
```

### Primary Category
```
Sports
```

### Secondary Category (optional)
```
Lifestyle
```

### Content Rights
```
Does this app contain, show, or access third-party content? → No
```

---

## 3. App Store Connect — Pricing and Availability

### Price
```
Free
```

### Availability
```
Available in all territories (or limit to: Canada, United States — since the court is in Toronto)
```
Recommended: Start with **Canada and United States** only.

---

## 4. App Store Connect — Version Information

### Screenshots

**Required sizes (at minimum, provide these two):**

| Device | Size | Simulator to Use |
|--------|------|-----------------|
| 6.7" Display | 1290 x 2796 px | iPhone 16 Pro Max |
| 6.1" Display | 1179 x 2556 px | iPhone 16 Pro |

**Required screenshots (5-10, suggest these 5):**
1. **Month Calendar** — Shows the month view with some bookings (green dots on days)
2. **Day Schedule** — Shows time slots with available and booked slots
3. **Booking Creation** — Player picker with 2-3 players selected
4. **Booking Detail** — Shows a booking with player names
5. **Login Screen** — Shows the invite code entry (demonstrates privacy)

See the screenshot automation section below.

### Description (4000 chars max)
```
214 Pickle is a private pickleball court scheduling app designed for small groups. Book your court time, invite players, and stay organized — all in one place.

SHARED CALENDAR
See all bookings at a glance with a clean month view. Green dots show which days have games scheduled. Tap any day to see the full hour-by-hour schedule.

EASY BOOKING
Pick an available time slot (5 AM – 9 PM), select 2-4 players from your group, and book the court with one tap. Everyone gets notified instantly.

REAL-TIME UPDATES
Bookings appear live for all members — no refreshing needed. See what's available right now, without calling or texting.

NOTIFICATIONS
Get push notifications and emails when you're added to a game, when a booking is cancelled, and a reminder 1 hour before your match.

PRIVATE & INVITE-ONLY
Access is controlled by invite code. Only members with a valid code can join. Your group, your court, your schedule.

SIMPLE PROFILE
Set your display name, toggle push and email notifications on or off, and manage your account — all from one screen.

Built for small groups who share a private court. No payments, no ads, no complexity. Just book and play.
```

### Keywords (100 chars max, comma-separated)
```
pickleball,court booking,scheduling,sports,private court,booking app,court reservation,pickle
```

### Promotional Text (170 chars max, can be updated without new build)
```
Book your private pickleball court in seconds. Invite players, get notified, and never double-book again.
```

### Support URL
```
https://214-pickle.com/support
```

### Marketing URL (optional)
```
https://214-pickle.com
```

### What's New in This Version
```
Initial release! Book courts, invite players, and get notified — all from your iPhone.
```

---

## 5. App Privacy — Data Collection

Go to App Store Connect → App Privacy and answer:

### Privacy Policy URL
```
https://214-pickle.com/privacy
```

### Data Collection
**"Does your app collect any of the user's data?"** → **Yes**

Then declare each data type:

| Data Type | Category | Purpose | Linked to User? | Used for Tracking? |
|-----------|----------|---------|------------------|--------------------|
| Email Address | Contact Info | App Functionality | Yes | No |
| Name | Contact Info | App Functionality | Yes | No |
| User ID | Identifiers | App Functionality | Yes | No |

**That's it.** We don't collect:
- No payment info
- No location data
- No browsing/search history
- No diagnostics/crash logs (unless Xcode analytics is on — Apple handles that separately)
- No usage data beyond what Supabase collects internally
- No third-party advertising data

---

## 6. Age Rating

Answer the questionnaire in App Store Connect:

| Question | Answer |
|----------|--------|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Unrestricted Web Access | No |
| Gambling and Contests | No |

**Result: Age Rating 4+**

---

## 7. App Review Information

### Contact Information
```
First Name: Marcus
Last Name: Cohoon
Phone: [your phone number]
Email: support@214-pickle.com
```

### Sign-In Required: Yes

### Demo Account
```
Email: reviewer@214-pickle.com
Password: AppleReview2026!
```

**IMPORTANT:** You must create this demo account BEFORE submitting:
1. Open the app on a device or simulator
2. Enter invite code: `PICKLE214`
3. Sign up with email `reviewer@214-pickle.com` and password `AppleReview2026!`
4. Use display name: `App Reviewer`

### Notes for App Review
```
214 Pickle is a private court scheduling app for a small group of pickleball players who share a private court.

ACCESS: The app requires an invite code to use. Please use invite code "PICKLE214" if you need to create a new account, or use the demo credentials provided above.

FUNCTIONALITY: After signing in, you will see a month calendar. Tap any future date to see available time slots (5 AM - 9 PM Eastern). To create a booking, tap an available slot, select 2-4 players, and tap "Book Court." Bookings can be viewed and cancelled from the day schedule view.

PUSH NOTIFICATIONS: Push notification functionality requires a physical device. On the simulator, the app will function normally but push notifications will not be delivered.

This app is designed for a small private group (<50 users) who share access to a single pickleball court.
```

---

## 8. Export Compliance

### Does your app use encryption? → **Yes**

### Does your app qualify for any of the exemptions? → **Yes**

Select: **"Your app uses encryption that is exempt because it is limited to..."**

Check: **"Standard HTTPS/TLS for network connections"**

This is correct — the app only uses HTTPS to communicate with Supabase. No custom encryption.

### Does your app contain, display, or access third-party content? → **No**

---

## 9. Build Selection

Select the build you uploaded via Xcode. Make sure it shows:
- Bundle ID: `com.214-pickle`
- Version: 1.0
- Build: 1

---

## 10. Pre-Submission Checklist

- [ ] Website deployed at 214-pickle.com with working pages (index, support, privacy, terms)
- [ ] Demo account created (reviewer@214-pickle.com / AppleReview2026!)
- [ ] Screenshots uploaded for 6.7" and 6.1" devices (minimum)
- [ ] App name: "214 Pickle"
- [ ] Subtitle: "Private Court Scheduling"
- [ ] Description pasted
- [ ] Keywords pasted
- [ ] Promotional text pasted
- [ ] Support URL: https://214-pickle.com/support
- [ ] Privacy Policy URL: https://214-pickle.com/privacy
- [ ] Marketing URL: https://214-pickle.com
- [ ] Category: Sports
- [ ] Price: Free
- [ ] Age rating questionnaire completed (4+)
- [ ] App Privacy declarations completed (email, name, user ID)
- [ ] Export compliance answered (Yes encryption, exempt — standard HTTPS)
- [ ] App Review notes pasted with invite code and demo credentials
- [ ] Build selected
- [ ] Submit for Review

---

## 11. Screenshot Generation

Since the app needs real data to look good in screenshots, the fastest approach:

### Manual screenshot method:
1. Open the app on iPhone 16 Pro Max simulator
2. Sign in with a test account
3. Create a few test bookings with different players for upcoming days
4. Take screenshots of each screen (Cmd+S in Simulator, or Cmd+Shift+4 on device)
5. Screenshots save to Desktop

### Screens to capture:
1. **Login screen** (with invite code field visible)
2. **Month Calendar** (with green dots on several days)
3. **Day Schedule** (mix of available + booked slots)
4. **Booking Create** (3 players selected)
5. **Booking Detail** (showing player names and cancel button)

### Required sizes:
- **iPhone 16 Pro Max** (6.7") → 1290 x 2796
- **iPhone 16 Pro** (6.1") → 1179 x 2556

Run the app on both simulator sizes and capture.

### Adding marketing frames (optional but recommended):
Use a tool like [Shots.so](https://shots.so), [AppMockUp](https://app-mockup.com), or [Previewed](https://previewed.app) to add device frames and marketing text above each screenshot.

Suggested captions for each:
1. "Private. Invite-Only."
2. "Your Court at a Glance"
3. "Book in Seconds"
4. "Pick Your Players"
5. "Every Detail, One Tap"
