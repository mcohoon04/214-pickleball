# 214 Pickle — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete iOS app + Supabase backend for private pickleball court scheduling.

**Architecture:** SwiftUI iOS app talks to Supabase (Postgres + Auth + Realtime + Edge Functions). Supabase CLI manages the backend locally via Docker. One monorepo holds both the Xcode project and the `supabase/` backend directory. Notifications delivered via a single Edge Function invoked by pg_cron every 60s.

**Tech Stack:** Swift 5.10+ / SwiftUI (iOS 16+), Supabase (supabase-swift v2.0+, supabase-js v2 in Edge Functions), GoogleSignIn-iOS v9.0.0, Deno (Edge Functions runtime), PostgreSQL with RLS.

**Reference docs:** All research lives in `docs/`. Read the relevant doc before starting each task.

---

## Phase 0: Project Scaffolding & Repo Structure

### Task 0.1: Create repo structure

**Context:** We need a monorepo that holds both the iOS Xcode project and the Supabase backend. The iOS project is managed by Xcode (not SPM-standalone). The Supabase directory sits alongside it.

**Files:**
- Create directory structure (see below)

**Step 1: Create the directory layout**

```
214-pickleball/
├── CLAUDE.md                    # (exists)
├── BRIEF.md                     # (exists)
├── icon.png                     # (exists)
├── docs/                        # (exists)
├── supabase/                    # Supabase backend (created by `supabase init`)
│   ├── config.toml
│   ├── migrations/
│   ├── functions/
│   │   └── send-notifications/
│   │       └── index.ts
│   ├── seed.sql
│   └── .env.local               # local dev secrets (gitignored)
├── ios/                         # Xcode project lives here
│   └── PickleBall214/           # Xcode project directory
│       ├── PickleBall214.xcodeproj
│       └── PickleBall214/       # Swift sources
│           ├── App/
│           │   └── PickleBall214App.swift
│           ├── Config/
│           │   ├── SupabaseConfig.swift
│           │   ├── Theme.swift
│           │   └── Info.plist
│           ├── Models/
│           │   ├── Profile.swift
│           │   ├── Booking.swift
│           │   └── Notification.swift
│           ├── Services/
│           │   ├── AuthService.swift
│           │   ├── BookingService.swift
│           │   ├── NotificationService.swift
│           │   └── RealtimeService.swift
│           ├── Views/
│           │   ├── Auth/
│           │   │   ├── LoginView.swift
│           │   │   └── SignUpView.swift
│           │   ├── Calendar/
│           │   │   ├── MonthCalendarView.swift
│           │   │   └── DayCellView.swift
│           │   ├── Schedule/
│           │   │   ├── DayScheduleView.swift
│           │   │   └── TimeSlotRow.swift
│           │   ├── Booking/
│           │   │   ├── BookingCreateView.swift
│           │   │   ├── BookingDetailView.swift
│           │   │   └── PlayerPickerView.swift
│           │   └── Profile/
│           │       └── ProfileView.swift
│           └── Assets.xcassets/
│               ├── AccentColor.colorset/
│               └── AppIcon.appiconset/
└── .gitignore
```

**Step 2: Update .gitignore**

Ensure `.gitignore` covers:
```
# Supabase
supabase/.env.local
supabase/.env
supabase/functions/.env

# Xcode
ios/**/*.xcuserdata/
ios/**/DerivedData/
ios/**/*.xcworkspace/xcuserdata/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# macOS
.DS_Store

# Secrets
.env
.env.local
*.p8

# Remem
.remem/
```

**Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: update gitignore for iOS + Supabase monorepo"
```

---

### Task 0.2: Initialize Supabase project locally

**Ref:** `docs/supabase-cli-local-dev.md`

**Prerequisites (Marcus must complete first):**
- Docker Desktop installed and running
- Supabase CLI installed: `brew install supabase/tap/supabase`
- Supabase project created at supabase.com → note `project-ref`, `anon key`, `service_role key`, `project URL`

**Step 1: Initialize Supabase in the repo**

```bash
cd /Users/marcus/Desktop/personal/214-pickleball
supabase init
```

This creates `supabase/config.toml`.

**Step 2: Link to remote project**

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
```

**Step 3: Configure auth in config.toml**

Edit `supabase/config.toml` to disable email confirmation and configure Google OAuth:

```toml
[auth]
site_url = "com.214-pickle://callback"
enable_signup = true

[auth.email]
enable_confirmations = false

[auth.external.google]
enabled = true
client_id = "env(GOOGLE_CLIENT_ID)"
secret = "env(GOOGLE_CLIENT_SECRET)"
```

**Step 4: Create local .env for secrets**

Create `supabase/.env.local`:
```
GOOGLE_CLIENT_ID=<web-client-id-from-google-console>
GOOGLE_CLIENT_SECRET=<web-client-secret>
```

**Step 5: Start local stack and verify**

```bash
supabase start
supabase status
```

Expected: Studio at `http://localhost:54323`, API at `http://localhost:54321`.

**Step 6: Commit**

```bash
git add supabase/config.toml
git commit -m "chore: initialize Supabase project with auth config"
```

---

## Phase 1: Database Schema & Backend

### Task 1.1: Create the initial database migration

**Ref:** `docs/supabase-schema-design.md`, `docs/plans/2026-04-04-design-review.md` (schema changes needed)

**Files:**
- Create: `supabase/migrations/<timestamp>_initial_schema.sql`

**Step 1: Create migration file**

```bash
supabase migration new initial_schema
```

**Step 2: Write the full schema SQL**

Paste the full SQL from `docs/supabase-schema-design.md` into the migration file, with these modifications from the design review:

1. Add `retry_count` to `notifications` table:
```sql
retry_count smallint not null default 0,
```

2. Add operating hours check to `bookings`:
```sql
check (date_part('hour', starts_at at time zone 'America/Toronto') between 5 and 20),
```

3. Add `invite_codes` table:
```sql
create table public.invite_codes (
  code text primary key check (char_length(trim(code)) between 4 and 20),
  created_at timestamptz not null default timezone('utc', now()),
  is_active boolean not null default true
);

alter table public.invite_codes enable row level security;
-- No RLS select policy for authenticated — codes are validated via RPC only
```

4. Update `notifications_pending_queue_idx` to respect retry limit:
```sql
create index notifications_pending_queue_idx
  on public.notifications (status, scheduled_for)
  where status = 'pending' or (status = 'failed' and retry_count < 3);
```

**Step 3: Apply locally**

```bash
supabase db reset
```

Expected: Migration applies cleanly, all tables created.

**Step 4: Verify in Studio**

Open `http://localhost:54323` → Table Editor. Verify all 5 tables exist: `profiles`, `bookings`, `booking_players`, `notifications`, `invite_codes`.

**Step 5: Commit**

```bash
git add supabase/migrations/
git commit -m "feat: initial database schema with all tables, triggers, RLS, and indexes"
```

---

### Task 1.2: Create the `create_booking` RPC function

**Ref:** `docs/plans/2026-04-04-design-review.md` (Critical Fix section)

**Files:**
- Create: `supabase/migrations/<timestamp>_create_booking_rpc.sql`

**Step 1: Create migration**

```bash
supabase migration new create_booking_rpc
```

**Step 2: Write the RPC function**

```sql
create or replace function public.create_booking(
  p_starts_at timestamptz,
  p_player_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_id uuid;
  v_caller uuid := auth.uid();
  v_player_id uuid;
begin
  -- Validate caller is authenticated
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  -- Validate player count (2-4)
  if array_length(p_player_ids, 1) is null
     or array_length(p_player_ids, 1) < 2
     or array_length(p_player_ids, 1) > 4 then
    raise exception 'Must have between 2 and 4 players';
  end if;

  -- Validate caller is in the player list
  if not (v_caller = any(p_player_ids)) then
    raise exception 'Booking creator must be included as a player';
  end if;

  -- Validate no duplicate player IDs
  if (select count(distinct x) from unnest(p_player_ids) x) <> array_length(p_player_ids, 1) then
    raise exception 'Duplicate player IDs not allowed';
  end if;

  -- Validate starts_at is in the future
  if p_starts_at < timezone('utc', now()) then
    raise exception 'Cannot book in the past';
  end if;

  -- Validate operating hours (5 AM - 9 PM Toronto time)
  if date_part('hour', p_starts_at at time zone 'America/Toronto') not between 5 and 20 then
    raise exception 'Bookings allowed between 5 AM and 9 PM only';
  end if;

  -- Validate on-the-hour
  if date_part('minute', p_starts_at) <> 0 or date_part('second', p_starts_at) <> 0 then
    raise exception 'Bookings must start on the hour';
  end if;

  -- Insert booking
  insert into public.bookings (created_by, starts_at, ends_at)
  values (v_caller, p_starts_at, p_starts_at + interval '1 hour')
  returning id into v_booking_id;

  -- Insert all players
  foreach v_player_id in array p_player_ids loop
    insert into public.booking_players (booking_id, player_id, added_by)
    values (v_booking_id, v_player_id, v_caller);
  end loop;

  return v_booking_id;
end;
$$;

-- Only authenticated users can call this
revoke all on function public.create_booking(timestamptz, uuid[]) from public;
grant execute on function public.create_booking(timestamptz, uuid[]) to authenticated;
```

**Step 3: Create a `validate_invite_code` RPC for signup flow**

Add to the same migration:

```sql
create or replace function public.validate_invite_code(p_code text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.invite_codes
    where code = trim(p_code) and is_active = true
  );
$$;

-- Allow anon (pre-auth) callers to validate codes
revoke all on function public.validate_invite_code(text) from public;
grant execute on function public.validate_invite_code(text) to anon, authenticated;
```

**Step 4: Apply and test locally**

```bash
supabase db reset
```

**Step 5: Commit**

```bash
git add supabase/migrations/
git commit -m "feat: add create_booking and validate_invite_code RPC functions"
```

---

### Task 1.3: Create seed data for local development

**Files:**
- Create: `supabase/seed.sql`

**Step 1: Write seed SQL**

```sql
-- Seed invite code for local development
insert into public.invite_codes (code) values ('PICKLE214');

-- Note: Test users must be created via Supabase Auth API, not direct insert.
-- Use Studio UI at http://localhost:54323 or the app's signup flow.
-- After creating auth users, profiles are auto-created by the handle_new_user trigger.
```

**Step 2: Reset to apply**

```bash
supabase db reset
```

**Step 3: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat: add seed data with dev invite code"
```

---

### Task 1.4: Build the notification delivery Edge Function

**Ref:** `docs/supabase-edge-functions.md`, `docs/apns-server-sending.md`, `docs/supabase-email-notifications.md`

**Files:**
- Create: `supabase/functions/send-notifications/index.ts`

**Step 1: Create the function**

```bash
supabase functions new send-notifications
```

**Step 2: Write the Edge Function**

The function:
1. Creates a Supabase admin client (service role key)
2. Queries pending notifications where `scheduled_for <= now()` and `retry_count < 3`
3. Marks batch as `processing`
4. For each notification:
   - If channel = `push`: sends via APNs HTTP/2 (JWT signed with Web Crypto)
   - If channel = `email`: sends via Resend API
5. Updates status to `sent` or `failed` with retry_count increment

Write `supabase/functions/send-notifications/index.ts` with:

```ts
import { createClient } from 'npm:@supabase/supabase-js@2'

// --- APNs JWT helpers (from docs/apns-server-sending.md) ---

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

function base64urlEncode(obj: Record<string, unknown>): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)))
}

let cachedApnsKey: CryptoKey | null = null
let cachedApnsToken: string | null = null
let apnsTokenCreatedAt = 0
const APNS_TOKEN_TTL = 50 * 60 * 1000 // 50 min

async function getApnsKey(): Promise<CryptoKey> {
  if (cachedApnsKey) return cachedApnsKey
  const pem = Deno.env.get('APNS_P8_KEY')!
  const keyData = pemToArrayBuffer(pem)
  cachedApnsKey = await crypto.subtle.importKey(
    'pkcs8', keyData,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false, ['sign']
  )
  return cachedApnsKey
}

async function getApnsToken(): Promise<string> {
  if (cachedApnsToken && Date.now() - apnsTokenCreatedAt < APNS_TOKEN_TTL) {
    return cachedApnsToken
  }
  const key = await getApnsKey()
  const keyId = Deno.env.get('APNS_KEY_ID')!
  const teamId = Deno.env.get('APNS_TEAM_ID')!
  const header = base64urlEncode({ alg: 'ES256', kid: keyId })
  const claims = base64urlEncode({ iss: teamId, iat: Math.floor(Date.now() / 1000) })
  const unsigned = `${header}.${claims}`
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key,
    new TextEncoder().encode(unsigned)
  )
  cachedApnsToken = `${unsigned}.${base64url(new Uint8Array(sig))}`
  apnsTokenCreatedAt = Date.now()
  return cachedApnsToken
}

// --- Send push via APNs ---

async function sendPush(
  deviceToken: string, title: string, body: string
): Promise<{ success: boolean; status: number; error?: string }> {
  const bundleId = Deno.env.get('APNS_BUNDLE_ID')!
  const sandbox = Deno.env.get('APNS_SANDBOX') === 'true'
  const host = sandbox ? 'api.development.push.apple.com' : 'api.push.apple.com'
  const jwt = await getApnsToken()

  const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      'authorization': `bearer ${jwt}`,
      'apns-topic': bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      aps: { alert: { title, body }, sound: 'default' },
    }),
  })

  if (res.status === 200) return { success: true, status: 200 }
  const err = await res.json().catch(() => ({}))
  return { success: false, status: res.status, error: err.reason ?? 'unknown' }
}

// --- Send email via Resend ---

async function sendEmail(
  to: string, subject: string, body: string
): Promise<{ success: boolean; id?: string; error?: string }> {
  const apiKey = Deno.env.get('RESEND_API_KEY')!
  const fromEmail = Deno.env.get('RESEND_FROM_EMAIL') ?? 'noreply@send.214-pickle.com'

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ from: fromEmail, to, subject, html: `<p>${body}</p>` }),
  })

  const data = await res.json()
  if (res.ok) return { success: true, id: data.id }
  return { success: false, error: data.message ?? 'unknown' }
}

// --- Main handler ---

Deno.serve(async (_req: Request) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Fetch pending notifications ready to send
  const { data: notifications, error: fetchErr } = await supabase
    .from('notifications')
    .select('*, profiles!notifications_user_id_fkey(apns_device_token, email:id)')
    .in('status', ['pending', 'failed'])
    .lt('scheduled_for', new Date().toISOString())
    .lt('retry_count', 3)
    .order('scheduled_for', { ascending: true })
    .limit(50)

  if (fetchErr) {
    return new Response(JSON.stringify({ error: fetchErr.message }), { status: 500 })
  }

  if (!notifications || notifications.length === 0) {
    return new Response(JSON.stringify({ processed: 0 }), { status: 200 })
  }

  // Mark as processing
  const ids = notifications.map((n: { id: string }) => n.id)
  await supabase
    .from('notifications')
    .update({ status: 'processing' })
    .in('id', ids)

  let sent = 0
  let failed = 0

  for (const notif of notifications) {
    let success = false
    let errorMsg = ''
    let providerId = ''

    try {
      if (notif.channel === 'push') {
        const token = notif.profiles?.apns_device_token
        if (!token) {
          errorMsg = 'No device token'
        } else {
          const result = await sendPush(token, notif.title, notif.body)
          success = result.success
          if (!success) {
            errorMsg = result.error ?? `HTTP ${result.status}`
            // Handle 410 Unregistered — clear device token
            if (result.status === 410) {
              await supabase
                .from('profiles')
                .update({ apns_device_token: null })
                .eq('id', notif.user_id)
            }
          }
        }
      } else if (notif.channel === 'email') {
        // Get user email from auth.users via admin API
        const { data: userData } = await supabase.auth.admin.getUserById(notif.user_id)
        const email = userData?.user?.email
        if (!email) {
          errorMsg = 'No email address'
        } else {
          const result = await sendEmail(email, notif.title, notif.body)
          success = result.success
          providerId = result.id ?? ''
          if (!success) errorMsg = result.error ?? 'unknown'
        }
      }
    } catch (e) {
      errorMsg = e instanceof Error ? e.message : 'unknown error'
    }

    if (success) {
      await supabase
        .from('notifications')
        .update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          provider_message_id: providerId || null,
        })
        .eq('id', notif.id)
      sent++
    } else {
      await supabase
        .from('notifications')
        .update({
          status: 'failed',
          error_message: errorMsg,
          retry_count: (notif.retry_count ?? 0) + 1,
        })
        .eq('id', notif.id)
      failed++
    }
  }

  return new Response(
    JSON.stringify({ processed: notifications.length, sent, failed }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  )
})
```

**Step 3: Create local env file for function testing**

Create `supabase/functions/.env`:
```
APNS_KEY_ID=YOUR_KEY_ID
APNS_TEAM_ID=YOUR_TEAM_ID
APNS_BUNDLE_ID=com.214-pickle
APNS_P8_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_KEY_HERE\n-----END PRIVATE KEY-----"
APNS_SANDBOX=true
RESEND_API_KEY=re_YOUR_KEY
RESEND_FROM_EMAIL=noreply@send.214-pickle.com
```

**Step 4: Test locally**

```bash
supabase functions serve send-notifications --env-file supabase/functions/.env
```

In another terminal:
```bash
curl -X POST http://localhost:54321/functions/v1/send-notifications \
  -H "Authorization: Bearer <anon-key-from-supabase-status>" \
  -H "Content-Type: application/json"
```

Expected: `{"processed":0}` (no pending notifications yet).

**Step 5: Commit**

```bash
git add supabase/functions/send-notifications/
git commit -m "feat: notification delivery Edge Function (APNs + Resend)"
```

---

### Task 1.5: Create pg_cron migration for notification scheduling

**Ref:** `docs/supabase-edge-functions.md` section 5

**Files:**
- Create: `supabase/migrations/<timestamp>_notification_cron.sql`

**Step 1: Create migration**

```bash
supabase migration new notification_cron
```

**Step 2: Write cron setup SQL**

```sql
-- Store project URL and service role key in Vault for cron job
-- These values are set per-environment (local vs production)
-- For local dev, these are populated by seed.sql
-- For production, run these manually after deploy:
--   select vault.create_secret('<your-project-url>', 'project_url');
--   select vault.create_secret('<your-service-role-key>', 'service_role_key');

-- Create the cron job to invoke the notification Edge Function every minute
select
  cron.schedule(
    'send-pending-notifications',
    '* * * * *',
    $$
    select
      net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
               || '/functions/v1/send-notifications',
        headers := jsonb_build_object(
          'Content-type', 'application/json',
          'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
        ),
        body := '{}'::jsonb
      ) as request_id;
    $$
  );
```

**Step 3: Update seed.sql to include Vault secrets for local dev**

Append to `supabase/seed.sql`:
```sql
-- Vault secrets for local cron job (matches supabase start output)
select vault.create_secret('http://host.docker.internal:54321', 'project_url');
-- The service_role_key is output by `supabase status` — paste it here for local dev
-- select vault.create_secret('YOUR_LOCAL_SERVICE_ROLE_KEY', 'service_role_key');
```

**Step 4: Apply and verify**

```bash
supabase db reset
```

Check cron job exists: open Studio → SQL Editor → `select * from cron.job;`

**Step 5: Commit**

```bash
git add supabase/migrations/ supabase/seed.sql
git commit -m "feat: pg_cron job for notification delivery every 60s"
```

---

### Task 1.6: Deploy backend to production

**Prerequisites (Marcus must complete):**
- Supabase project created and linked
- Apple Developer: APNs key (.p8), Key ID, Team ID
- Resend: API key, verified sender email/domain

**Step 1: Push migrations**

```bash
supabase db push
```

**Step 2: Deploy Edge Function**

```bash
supabase functions deploy send-notifications --no-verify-jwt
```

`--no-verify-jwt` because the cron job calls it with the service role key, not a user JWT.

**Step 3: Set production secrets**

```bash
supabase secrets set APNS_KEY_ID=<key-id>
supabase secrets set APNS_TEAM_ID=<team-id>
supabase secrets set APNS_BUNDLE_ID=com.214-pickle
supabase secrets set "APNS_P8_KEY=<full-.p8-contents>"
supabase secrets set APNS_SANDBOX=false
supabase secrets set RESEND_API_KEY=<resend-key>
supabase secrets set RESEND_FROM_EMAIL=noreply@send.214-pickle.com
```

**Step 4: Set Vault secrets for cron (via SQL Editor in Dashboard)**

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<service-role-key>', 'service_role_key');
```

**Step 5: Insert production invite code**

In Dashboard SQL Editor:
```sql
insert into public.invite_codes (code) values ('PICKLE214');
```

**Step 6: Verify**

Check Dashboard → Edge Functions → `send-notifications` shows as deployed.
Check Dashboard → SQL Editor → `select * from cron.job;` shows the scheduled job.

**Step 7: Commit any config changes**

```bash
git add -A && git commit -m "chore: production deployment config"
```

---

## Phase 2: iOS App Foundation

### Task 2.1: Create Xcode project

**Step 1: Create the Xcode project via Xcode CLI or GUI**

1. Product Name: `PickleBall214`
2. Organization Identifier: `com.214-pickle`
3. Bundle Identifier: `com.214-pickle`
4. Interface: SwiftUI, Language: Swift
5. Save to: `ios/` directory in the repo
6. Add SPM dependencies (File → Add Package Dependencies):
   - `https://github.com/supabase/supabase-swift.git` (from: 2.0.0) → product: `Supabase`
   - `https://github.com/google/GoogleSignIn-iOS` (from: 9.0.0) → products: `GoogleSignIn`, `GoogleSignInSwift`
7. In target → Signing & Capabilities:
   - Add "Push Notifications"
   - Add "Sign in with Apple"
   - Add "Background Modes" → enable "Remote notifications"
   - Set Team to "None" (Marcus will select his team for final archive/upload)
8. In target → Info → URL Types:
   - Add URL scheme: reversed Google iOS client ID (`com.googleusercontent.apps.849098110880-fpibqeeeofjqqnlku57n9nhf45kcpu4u`)
9. In target → Info → Custom iOS Target Properties:
   - `GIDClientID` = `849098110880-fpibqeeeofjqqnlku57n9nhf45kcpu4u.apps.googleusercontent.com`

**Step 2: Commit the Xcode project skeleton**

```bash
git add ios/
git commit -m "chore: create Xcode project with SPM dependencies"
```

---

### Task 2.2: Theme and configuration

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Config/Theme.swift`
- Create: `ios/PickleBall214/PickleBall214/Config/SupabaseConfig.swift`

**Step 1: Write Theme.swift**

```swift
import SwiftUI

enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.12)
    static let surfaceLight = Color(white: 0.18)
    static let accent = Color(red: 0.478, green: 0.757, blue: 0.263) // #7AC143
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.6)
    static let textOnAccent = Color.black
    static let destructive = Color.red
    static let disabled = Color(white: 0.3)

    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 16
}
```

**Step 2: Write SupabaseConfig.swift**

```swift
import Supabase

enum SupabaseConfig {
    // TODO: Marcus — replace with your actual project values
    static let url = URL(string: "https://YOUR_PROJECT_REF.supabase.co")!
    static let anonKey = "YOUR_ANON_KEY"

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: anonKey,
        options: SupabaseClientOptions(
            db: .init(schema: "public"),
            auth: .init(flowType: .pkce)
        )
    )
}
```

**Step 3: Set up AccentColor asset**

Update `Assets.xcassets/AccentColor.colorset/Contents.json` to use `#7AC143`.

**Step 4: Set up AppIcon asset**

Copy `icon.png` from repo root into the `AppIcon.appiconset` and update its `Contents.json` for a single 1024x1024 icon (modern Xcode auto-generates all sizes from one source).

**Step 5: Commit**

```bash
git add ios/PickleBall214/
git commit -m "feat: theme config and Supabase client setup"
```

---

### Task 2.3: Data models

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Models/Profile.swift`
- Create: `ios/PickleBall214/PickleBall214/Models/Booking.swift`

**Step 1: Write Profile.swift**

```swift
import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var avatarUrl: String?
    var timezone: String
    var pushEnabled: Bool
    var emailEnabled: Bool
    var apnsDeviceToken: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case timezone
        case pushEnabled = "push_enabled"
        case emailEnabled = "email_enabled"
        case apnsDeviceToken = "apns_device_token"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PlayerInfo: Codable, Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}
```

**Step 2: Write Booking.swift**

```swift
import Foundation

struct Booking: Codable, Identifiable, Hashable {
    let id: UUID
    let createdBy: UUID
    let startsAt: Date
    let endsAt: Date
    let status: BookingStatus
    let cancelledAt: Date?
    let cancelledBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case createdBy = "created_by"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
        case cancelledAt = "cancelled_at"
        case cancelledBy = "cancelled_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum BookingStatus: String, Codable, Hashable {
    case active
    case cancelled
}

struct BookingWithPlayers: Identifiable, Hashable {
    let booking: Booking
    let players: [PlayerInfo]
    var id: UUID { booking.id }
}

struct BookingPlayer: Codable {
    let bookingId: UUID
    let playerId: UUID
    let addedBy: UUID

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case playerId = "player_id"
        case addedBy = "added_by"
    }
}

struct TimeSlot: Identifiable, Hashable {
    let hour: Int
    let date: Date
    var booking: BookingWithPlayers?
    var id: String { "\(date.timeIntervalSince1970)-\(hour)" }
    var isAvailable: Bool { booking == nil }
}
```

**Step 3: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Models/
git commit -m "feat: data models for Profile, Booking, and TimeSlot"
```

---

### Task 2.4: Auth service

**Ref:** `docs/supabase-ios.md`, `docs/google-signin-ios.md`, Supabase Apple auth docs

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Services/AuthService.swift`

**Step 1: Write AuthService.swift**

```swift
import Foundation
import Supabase
import GoogleSignIn

@Observable
final class AuthService {
    var currentUser: Profile?
    var isAuthenticated = false
    var isLoading = true
    var errorMessage: String?

    private let supabase = SupabaseConfig.client

    init() {
        Task { await listenForAuthChanges() }
    }

    private func listenForAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            await MainActor.run {
                switch event {
                case .initialSession:
                    self.isAuthenticated = session != nil
                    self.isLoading = false
                case .signedIn:
                    self.isAuthenticated = true
                case .signedOut:
                    self.isAuthenticated = false
                    self.currentUser = nil
                default:
                    break
                }
            }
            if session != nil {
                await loadProfile()
            }
        }
    }

    func signUp(email: String, password: String, displayName: String, inviteCode: String) async throws {
        // Validate invite code first
        let isValid: Bool = try await supabase.rpc("validate_invite_code", params: ["p_code": inviteCode]).execute().value
        guard isValid else {
            throw AuthError.invalidInviteCode
        }

        try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(displayName)]
        )
    }

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
                if let error { continuation.resume(throwing: error); return }
                guard let result else { continuation.resume(throwing: AuthError.googleSignInFailed); return }
                continuation.resume(returning: result)
            }
        }

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.googleSignInFailed
        }

        try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
        )
    }

    // MARK: - Apple Sign-In

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )

        // Apple only provides the user's name on first sign-in — capture it immediately
        if let fullName {
            var parts: [String] = []
            if let given = fullName.givenName { parts.append(given) }
            if let family = fullName.familyName { parts.append(family) }
            let name = parts.joined(separator: " ")
            if !name.isEmpty {
                try? await updateProfile(displayName: name)
            }
        }
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    func loadProfile() async {
        guard let userId = try? await supabase.auth.session.user.id else { return }
        do {
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            await MainActor.run { self.currentUser = profile }
        } catch {
            print("Failed to load profile: \(error)")
        }
    }

    func updateProfile(displayName: String? = nil, pushEnabled: Bool? = nil, emailEnabled: Bool? = nil) async throws {
        guard let userId = currentUser?.id else { return }
        var updates: [String: AnyJSON] = [:]
        if let displayName { updates["display_name"] = .string(displayName) }
        if let pushEnabled { updates["push_enabled"] = .bool(pushEnabled) }
        if let emailEnabled { updates["email_enabled"] = .bool(emailEnabled) }

        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId)
            .execute()

        await loadProfile()
    }

    func updateDeviceToken(_ token: String) async throws {
        guard let userId = currentUser?.id else { return }
        try await supabase
            .from("profiles")
            .update(["apns_device_token": token])
            .eq("id", value: userId)
            .execute()
    }

    enum AuthError: LocalizedError {
        case invalidInviteCode
        case googleSignInFailed
        case appleSignInFailed

        var errorDescription: String? {
            switch self {
            case .invalidInviteCode: return "Invalid invite code"
            case .googleSignInFailed: return "Google sign-in failed"
            case .appleSignInFailed: return "Apple sign-in failed"
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Services/AuthService.swift
git commit -m "feat: auth service with email/password, Google Sign-In, Apple Sign-In, and invite code validation"
```

---

### Task 2.5: Booking service

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Services/BookingService.swift`

**Step 1: Write BookingService.swift**

```swift
import Foundation
import Supabase

@Observable
final class BookingService {
    var bookingsForMonth: [Booking] = []
    var bookingsForDay: [BookingWithPlayers] = []
    var allPlayers: [PlayerInfo] = []

    private let supabase = SupabaseConfig.client
    private let calendar = Calendar.current
    private let torontoTimeZone = TimeZone(identifier: "America/Toronto")!

    func fetchBookingsForMonth(year: Int, month: Int) async throws {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.timeZone = torontoTimeZone

        guard let monthStart = calendar.date(from: components),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return }

        let bookings: [Booking] = try await supabase
            .from("bookings")
            .select()
            .eq("status", value: "active")
            .gte("starts_at", value: monthStart.ISO8601Format())
            .lt("starts_at", value: monthEnd.ISO8601Format())
            .execute()
            .value

        await MainActor.run { self.bookingsForMonth = bookings }
    }

    func fetchBookingsForDay(date: Date) async throws {
        var cal = calendar
        cal.timeZone = torontoTimeZone
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }

        let bookings: [Booking] = try await supabase
            .from("bookings")
            .select()
            .eq("status", value: "active")
            .gte("starts_at", value: dayStart.ISO8601Format())
            .lt("starts_at", value: dayEnd.ISO8601Format())
            .order("starts_at")
            .execute()
            .value

        // Fetch players for each booking
        var withPlayers: [BookingWithPlayers] = []
        for booking in bookings {
            let players: [PlayerInfo] = try await supabase
                .from("booking_players")
                .select("player_id, profiles!booking_players_player_id_fkey(id, display_name, avatar_url)")
                .eq("booking_id", value: booking.id)
                .execute()
                .value
            // Note: may need to adjust the select/decode pattern depending on
            // how supabase-swift handles nested joins. Test and adjust.
            withPlayers.append(BookingWithPlayers(booking: booking, players: players))
        }

        await MainActor.run { self.bookingsForDay = withPlayers }
    }

    func fetchAllPlayers() async throws {
        let players: [PlayerInfo] = try await supabase
            .rpc("list_players")
            .execute()
            .value

        await MainActor.run { self.allPlayers = players }
    }

    func createBooking(startsAt: Date, playerIds: [UUID]) async throws -> UUID {
        struct CreateBookingParams: Encodable {
            let p_starts_at: String
            let p_player_ids: [UUID]
        }

        let result: UUID = try await supabase
            .rpc("create_booking", params: CreateBookingParams(
                p_starts_at: startsAt.ISO8601Format(),
                p_player_ids: playerIds
            ))
            .execute()
            .value

        return result
    }

    func cancelBooking(id: UUID) async throws {
        try await supabase
            .from("bookings")
            .update(["status": "cancelled"])
            .eq("id", value: id)
            .execute()
    }

    func timeSlotsForDay(date: Date) -> [TimeSlot] {
        var cal = calendar
        cal.timeZone = torontoTimeZone
        let dayStart = cal.startOfDay(for: date)

        return (5...20).map { hour in
            let slotDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart)!
            let match = bookingsForDay.first { bwp in
                let bookingHour = cal.component(.hour, from: bwp.booking.startsAt)
                return cal.isDate(bwp.booking.startsAt, inSameDayAs: date) && bookingHour == hour
            }
            return TimeSlot(hour: hour, date: slotDate, booking: match)
        }
    }
}
```

**Step 2: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Services/BookingService.swift
git commit -m "feat: booking service with create, cancel, fetch, and time slot generation"
```

---

### Task 2.6: Realtime service

**Ref:** `docs/supabase-ios.md` section 4

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Services/RealtimeService.swift`

**Step 1: Write RealtimeService.swift**

```swift
import Foundation
import Supabase

@Observable
final class RealtimeService {
    private let supabase = SupabaseConfig.client
    private var channel: RealtimeChannelV2?

    func subscribeToBookingChanges(onChange: @escaping () -> Void) async {
        let channel = supabase.channel("booking-changes")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "bookings"
        )

        await channel.subscribe()
        self.channel = channel

        Task {
            for await _ in changes {
                await MainActor.run { onChange() }
            }
        }
    }

    func unsubscribe() async {
        if let channel {
            await supabase.removeChannel(channel)
            self.channel = nil
        }
    }
}
```

**Step 2: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Services/RealtimeService.swift
git commit -m "feat: realtime service for live booking updates"
```

---

### Task 2.7: Push notification registration

**Ref:** `docs/apple-push-notifications.md`

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Services/NotificationService.swift`

**Step 1: Write NotificationService.swift**

```swift
import Foundation
import UIKit
import UserNotifications

final class PushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    var onTokenReceived: ((String) -> Void)?

    func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        onTokenReceived?(token)
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }
}
```

**Step 2: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Services/NotificationService.swift
git commit -m "feat: push notification registration and token handling"
```

---

## Phase 3: iOS Views

### Task 3.1: App entry point and auth guard

**Files:**
- Modify: `ios/PickleBall214/PickleBall214/App/PickleBall214App.swift`

**Step 1: Write the app entry point**

```swift
import SwiftUI
import GoogleSignIn

@main
struct PickleBall214App: App {
    @State private var authService = AuthService()
    @State private var bookingService = BookingService()
    @State private var realtimeService = RealtimeService()
    private let pushService = PushNotificationService()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                } else if authService.isAuthenticated {
                    MainView()
                        .environment(authService)
                        .environment(bookingService)
                        .environment(realtimeService)
                } else {
                    LoginView()
                        .environment(authService)
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    var pushService = PushNotificationService()

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushService.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Push registration failed: \(error)")
    }
}
```

**Step 2: Commit**

```bash
git add ios/PickleBall214/
git commit -m "feat: app entry point with auth guard, push setup, and Google URL handling"
```

---

### Task 3.2: Login and SignUp views

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Views/Auth/LoginView.swift`
- Create: `ios/PickleBall214/PickleBall214/Views/Auth/SignUpView.swift`

**Step 1: Write LoginView.swift**

Login screen with email/password form, Google Sign-In button, and link to Sign Up. Dark theme with green accent. Show the 214 Pickle icon at top.

Key elements:
- Email + password fields
- "Sign In" button (green accent)
- "Sign in with Apple" button (using native `SignInWithAppleButton` from `AuthenticationServices`)
  - Generate raw nonce + SHA-256 hash, pass hash to Apple request, pass raw nonce to Supabase
  - Capture `credential.fullName` on first sign-in (Apple only provides it once)
- Google Sign-In button (using `GoogleSignInButton`)
- "Don't have an account? Sign Up" link
- Error message display

**Step 2: Write SignUpView.swift**

Sign up screen with invite code field, name, email, password fields, and submit button.

Key elements:
- Invite code field (validated via RPC before proceeding)
- Display name field
- Email + password fields
- "Create Account" button
- Error message display
- "Already have an account? Sign In" link

**Step 3: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Views/Auth/
git commit -m "feat: login and signup views with invite code validation"
```

---

### Task 3.3: Month Calendar view

**Ref:** `docs/swiftui-calendar.md`

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Views/Calendar/MonthCalendarView.swift`
- Create: `ios/PickleBall214/PickleBall214/Views/Calendar/DayCellView.swift`

**Step 1: Write MonthCalendarView.swift**

Main landing screen. Month grid using `LazyVGrid` with 7 columns. Shows:
- Month/year header with left/right arrows to navigate months
- Weekday labels (S M T W T F S)
- Day cells: past days greyed out, today highlighted, days with bookings show green dot
- Tap a day → push `DayScheduleView` via NavigationLink(value:)
- Toolbar button for Profile (gear icon)

Use `BookingService.fetchBookingsForMonth()` on appear and month change.

**Step 2: Write DayCellView.swift**

Individual day cell. Shows day number, optional green dot for bookings, disabled/greyed for past days, today has green border.

**Step 3: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Views/Calendar/
git commit -m "feat: month calendar view with booking indicators and navigation"
```

---

### Task 3.4: Day Schedule view

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Views/Schedule/DayScheduleView.swift`
- Create: `ios/PickleBall214/PickleBall214/Views/Schedule/TimeSlotRow.swift`

**Step 1: Write DayScheduleView.swift**

Hour-by-hour schedule for a selected day (5 AM - 9 PM). ScrollView of `TimeSlotRow`s.
- Navigation title: formatted date (e.g., "Sat, Apr 5")
- Each row shows the hour and status (Available / Booked with player names)
- Available slots are tappable → push BookingCreateView
- Booked slots show player names and are tappable → push BookingDetailView
- Load data via `BookingService.fetchBookingsForDay(date:)`
- Subscribe to Realtime on appear, unsubscribe on disappear

**Step 2: Write TimeSlotRow.swift**

Single time slot row. Shows:
- Hour label (e.g., "10 AM")
- If available: "Available" in green, tappable
- If booked: player names, green accent left border, tappable for detail
- If booked by current user: slightly different styling (e.g., "Your booking" label)
- Past slots: greyed out, not tappable

**Step 3: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Views/Schedule/
git commit -m "feat: day schedule view with time slot rows and realtime updates"
```

---

### Task 3.5: Booking Create view with Player Picker

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Views/Booking/BookingCreateView.swift`
- Create: `ios/PickleBall214/PickleBall214/Views/Booking/PlayerPickerView.swift`

**Step 1: Write BookingCreateView.swift**

Booking creation screen:
- Shows selected date/time at top
- "Select Players" section with player picker
- Current user auto-included (shown but can't be removed)
- Must select 1-3 additional players
- "Book Court" button (green, disabled until valid selection)
- On success: pop back to day schedule
- On error: show error message

Calls `BookingService.createBooking(startsAt:playerIds:)`.

**Step 2: Write PlayerPickerView.swift**

List of all players from `BookingService.allPlayers`. Each row shows:
- Player name and avatar
- Checkmark if selected
- Current user row is pre-selected and non-toggleable
- Selection count indicator (e.g., "2/4 players selected")

**Step 3: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Views/Booking/
git commit -m "feat: booking creation view with player picker"
```

---

### Task 3.6: Booking Detail view

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Views/Booking/BookingDetailView.swift`

**Step 1: Write BookingDetailView.swift**

Shows booking details:
- Date and time
- Player list with names
- "Created by [name]" label
- If current user is the creator: "Cancel Booking" button (red/destructive)
- Confirmation dialog before cancellation
- On cancel: calls `BookingService.cancelBooking(id:)`, pops back

**Step 2: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Views/Booking/BookingDetailView.swift
git commit -m "feat: booking detail view with cancel capability"
```

---

### Task 3.7: Profile / Settings view

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Views/Profile/ProfileView.swift`

**Step 1: Write ProfileView.swift**

Settings screen:
- Display name (editable)
- Email (read-only, from auth)
- Push notifications toggle
- Email notifications toggle
- "Save" button for changes
- "Sign Out" button at bottom (destructive style)

Uses `AuthService.updateProfile()` and `AuthService.signOut()`.

**Step 2: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Views/Profile/
git commit -m "feat: profile view with notification preferences and sign out"
```

---

### Task 3.8: Main navigation wrapper

**Files:**
- Create: `ios/PickleBall214/PickleBall214/Views/MainView.swift`

**Step 1: Write MainView.swift**

Root view for authenticated users. Single `NavigationStack` with `NavigationPath`:

```swift
struct MainView: View {
    @State private var path = NavigationPath()
    @State private var showingProfile = false
    @Environment(AuthService.self) var authService
    @Environment(BookingService.self) var bookingService
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            MonthCalendarView(path: $path)
                .navigationDestination(for: Date.self) { date in
                    DayScheduleView(date: date, path: $path)
                }
                .navigationDestination(for: TimeSlot.self) { slot in
                    BookingCreateView(slot: slot, path: $path)
                }
                .navigationDestination(for: BookingWithPlayers.self) { bwp in
                    BookingDetailView(booking: bwp, path: $path)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingProfile = true } label: {
                            Image(systemName: "person.circle")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .sheet(isPresented: $showingProfile) {
                    ProfileView()
                }
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    // Re-fetch on foreground resume
                    let now = Date()
                    let cal = Calendar.current
                    try? await bookingService.fetchBookingsForMonth(
                        year: cal.component(.year, from: now),
                        month: cal.component(.month, from: now)
                    )
                }
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add ios/PickleBall214/PickleBall214/Views/MainView.swift
git commit -m "feat: main navigation with NavigationStack, path routing, and foreground refresh"
```

---

## Phase 4: Integration & Polish

### Task 4.1: Wire up push notification token to profile

**Files:**
- Modify: `ios/PickleBall214/PickleBall214/App/PickleBall214App.swift`

**Step 1: Connect push token to auth service**

In the app entry point, after authentication succeeds:
1. Request push notification permission
2. When token received, call `authService.updateDeviceToken(token)`

Wire the `AppDelegate.pushService.onTokenReceived` callback to save the token via `AuthService`.

**Step 2: Commit**

```bash
git add ios/PickleBall214/
git commit -m "feat: wire push notification token to user profile on auth"
```

---

### Task 4.2: Foreground refresh and realtime integration in views

**Files:**
- Modify: Views as needed

**Step 1: Ensure DayScheduleView subscribes to Realtime**

On `.onAppear`: subscribe to booking changes via `RealtimeService`. On change callback: re-fetch bookings for the current day. On `.onDisappear`: unsubscribe.

**Step 2: Ensure MonthCalendarView refreshes on Realtime**

Subscribe to booking changes at the month level. On change: re-fetch month bookings.

**Step 3: Commit**

```bash
git add ios/PickleBall214/
git commit -m "feat: realtime subscription in calendar and schedule views"
```

---

### Task 4.3: Error handling and loading states

**Files:**
- Modify: All views

**Step 1: Add loading states**

Each view that fetches data should show a `ProgressView` while loading. Use `@State private var isLoading = true` pattern.

**Step 2: Add error alerts**

Show `.alert` modifiers for booking creation/cancellation failures, network errors, and auth errors.

**Step 3: Add empty states**

DayScheduleView: "No bookings today — tap a slot to book!" when all slots are available.

**Step 4: Commit**

```bash
git add ios/PickleBall214/
git commit -m "feat: loading states, error alerts, and empty states across all views"
```

---

### Task 4.4: Final polish and visual consistency

**Files:**
- Modify: All views

**Step 1: Verify theme consistency**

Walk through every view and ensure:
- Black backgrounds everywhere
- White primary text
- Green accents on interactive elements
- `Theme.surface` for card-like containers
- `Theme.cornerRadius` on all rounded elements
- Proper spacing with `Theme.padding`

**Step 2: Verify dark mode**

The app forces `.preferredColorScheme(.dark)`. Verify all system components (alerts, sheets, pickers) look correct.

**Step 3: Commit**

```bash
git add ios/PickleBall214/
git commit -m "chore: visual polish and theme consistency pass"
```

---

## Phase 5: Deploy & Test End-to-End

### Task 5.1: Deploy backend to production

Follow Task 1.6 steps (push migrations, deploy function, set secrets, set Vault secrets, insert invite code).

### Task 5.2: Configure Supabase project settings

**Already completed by Marcus:**
1. ~~Authentication → Providers → Google: enable, enter Web + iOS client IDs, secret, skip nonce checks ON~~ ✓
2. ~~Authentication → Providers → Apple: enable, enter client IDs (`com.214-pickle,com.214-pickle.web`), JWT secret~~ ✓
3. Authentication → Settings: disable "Confirm email"
4. Authentication → URL Configuration: add `com.214-pickle://callback` to redirect URLs

### Task 5.3: Configure Xcode with real values

**Marcus does (before archive/upload):**
1. Open Xcode project, select his Apple Developer team for signing
2. Update `SupabaseConfig.swift` with real project URL (`https://ttdeyiriqminwguozbal.supabase.co`) and publishable key
3. Verify bundle ID matches APNs key configuration (`com.214-pickle`)

### Task 5.4: End-to-end testing checklist

1. Sign up with invite code "PICKLE214" → profile created
2. Sign in with email/password → lands on calendar
3. Sign in with Google → lands on calendar
4. Sign in with Apple → lands on calendar
5. Navigate months in calendar
5. Tap a day → see hour-by-hour schedule
6. Book a slot with 2 players → booking appears immediately
7. Other user sees booking appear (Realtime)
8. Cancel own booking → booking disappears
9. Push notification received when added to booking
10. Email notification received when added to booking
11. Reminder push received 1 hour before booking
12. Profile: change display name → persists
13. Profile: toggle notifications → persists
14. Sign out → returns to login
15. Background app → resume → data refreshes

### Task 5.5: Build and upload

**Marcus does:**
1. Xcode → Product → Archive
2. Validate archive
3. Upload to App Store Connect
4. TestFlight: create external testing group, invite testers
5. Submit for beta review

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| 0 | 0.1-0.2 | Repo structure, Supabase initialized |
| 1 | 1.1-1.6 | Complete backend: schema, RPC, Edge Function, cron, deployed |
| 2 | 2.1-2.7 | iOS foundation: project, theme, models, services |
| 3 | 3.1-3.8 | All 4 app views + navigation |
| 4 | 4.1-4.4 | Integration, realtime, push, polish |
| 5 | 5.1-5.5 | Deploy, configure, test, ship |

**Total tasks:** 22 (2 require Marcus: Supabase deploy config + final archive/upload, rest are Claude Code)

## Pre-Implementation Setup (Completed by Marcus)

| Item | Status | Details |
|------|--------|---------|
| Docker + Supabase CLI | ✓ | Docker 29.1.3, Supabase CLI 2.84.2 |
| Supabase project | ✓ | `ttdeyiriqminwguozbal`, linked to CLI |
| Google OAuth (iOS) | ✓ | `849098110880-fpibqeeeofjqqnlku57n9nhf45kcpu4u.apps.googleusercontent.com` |
| Google OAuth (Web) | ✓ | Configured in Supabase Dashboard (skip nonce checks ON) |
| Apple Sign-In | ✓ | App ID capability, Services ID `com.214-pickle.web`, JWT secret (expires 2026-10-01) |
| APNs key | ✓ | Key ID `35B2VVD689`, Team ID `CJJY27BA49`, shared .p8 with Apple Sign-In |
| Resend | ✓ | Domain `send.214-pickle.com` verified, from address `noreply@send.214-pickle.com` |
| DNS | ✓ | Cloudflare, email routing to `team@214-pickle.com` |
| Bundle ID | ✓ | `com.214-pickle` (registered in App Store Connect, Apple ID `6761661861`) |
