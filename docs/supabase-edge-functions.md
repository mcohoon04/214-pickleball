# Supabase Edge Functions Research

## Scope
Edge Functions for the notification delivery worker: creating, deploying, secrets, database webhooks, and scheduled invocation via pg_cron.

## Primary Sources
- Edge Functions overview:
  - https://supabase.com/docs/guides/functions
- Edge Function secrets:
  - https://supabase.com/docs/guides/functions/secrets
- Push notifications example:
  - https://supabase.com/docs/guides/functions/examples/push-notifications
- Database webhooks:
  - https://supabase.com/docs/guides/database/webhooks
- Scheduling with pg_cron:
  - https://supabase.com/docs/guides/functions/schedule-functions
- CLI reference:
  - https://supabase.com/docs/reference/cli/introduction

## 1) Edge Functions Basics

Edge Functions run on **Supabase Edge Runtime**, a Deno-compatible environment. Functions are TypeScript files that export a handler.

### File structure
```
supabase/
  functions/
    my-function/
      index.ts
    another-function/
      index.ts
```

### Creating a function
```bash
supabase functions new my-function
```

### Basic handler pattern
```ts
Deno.serve(async (req: Request) => {
  const { name } = await req.json()
  const data = { message: `Hello ${name}!` }
  return new Response(JSON.stringify(data), {
    headers: { 'Content-Type': 'application/json' },
  })
})
```

### Local development
```bash
supabase functions serve           # serves all functions
supabase functions serve my-func   # serves one function
supabase functions serve --env-file .env.local  # with local secrets
```

### Deployment
```bash
supabase functions deploy my-function
supabase functions deploy my-function --no-verify-jwt  # skip JWT validation
```

## 2) Secrets Management

### Default secrets (automatically available)
- `SUPABASE_URL` — API gateway URL
- `SUPABASE_ANON_KEY` — anon key (safe for browser, respects RLS)
- `SUPABASE_SERVICE_ROLE_KEY` — admin key (bypasses RLS, never in browser)
- `SUPABASE_DB_URL` — direct Postgres connection string

Additional runtime variables: `SB_REGION`, `SB_EXECUTION_ID`, `DENO_DEPLOYMENT_ID`.

### Accessing secrets in code
```ts
Deno.env.get('SUPABASE_URL')
Deno.env.get('MY_CUSTOM_SECRET')
```

### Setting secrets (production)
```bash
supabase secrets set MY_KEY=my_value
supabase secrets set --env-file .env
supabase secrets list
```

Secrets are available immediately — no redeployment needed.

### Local development secrets
Place in `supabase/functions/.env` (auto-loaded) or specify:
```bash
supabase functions serve --env-file .env.local
```

Add `.env` files to `.gitignore`.

## 3) Creating a Supabase Client Inside Edge Functions

```ts
import { createClient } from 'npm:@supabase/supabase-js@2'

// Respects RLS (use with user's JWT)
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_ANON_KEY')!
)

// Bypasses RLS (admin operations)
const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)
```

For the notification worker, use the admin client to read/update `notifications` table rows regardless of RLS.

## 4) Database Webhooks

Webhooks use the `pg_net` extension to send HTTP requests when table events occur. They are async triggers — they don't block the database operation.

### Supported events
- `INSERT` — after a row is added
- `UPDATE` — after a row is modified
- `DELETE` — after a row is removed

### Dashboard setup
1. Database → Webhooks → Create
2. Name the webhook
3. Select table (e.g., `notifications`)
4. Enable event type(s) (e.g., INSERT)
5. Set Edge Function URL: `https://<project-ref>.supabase.co/functions/v1/push`
6. HTTP Method: POST, Timeout: 1000ms
7. Add header: `Authorization: Bearer <service_role_key>`
8. Content-type: `application/json`

### SQL creation
```sql
create trigger "my_webhook" after insert
on "public"."notifications" for each row
execute function "supabase_functions"."http_request"(
  'https://<project-ref>.supabase.co/functions/v1/push',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer <service_role_key>"}',
  '{}',
  '1000'
);
```

### Webhook payload format

INSERT:
```json
{
  "type": "INSERT",
  "table": "notifications",
  "schema": "public",
  "record": { /* new row data */ },
  "old_record": null
}
```

UPDATE:
```json
{
  "type": "UPDATE",
  "table": "notifications",
  "schema": "public",
  "record": { /* updated row data */ },
  "old_record": { /* previous row data */ }
}
```

### Local development note
In Docker, `localhost` resolves to the container. Use `host.docker.internal` to reach host machine:
```
http://host.docker.internal:54321/functions/v1/my-function
```

## 5) Scheduling with pg_cron + pg_net

For the notification worker polling pattern (send pending notifications on a schedule).

### Store credentials in Vault
```sql
select vault.create_secret('https://project-ref.supabase.co', 'project_url');
select vault.create_secret('YOUR_SUPABASE_ANON_KEY', 'anon_key');
```

### Create cron job
```sql
select
  cron.schedule(
    'send-pending-notifications',
    '* * * * *',  -- every minute
    $$
    select
      net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
               || '/functions/v1/send-notifications',
        headers := jsonb_build_object(
          'Content-type', 'application/json',
          'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'anon_key')
        ),
        body := concat('{"time": "', now(), '"}')::jsonb
      ) as request_id;
    $$
  );
```

Uses `net.http_post()` from `pg_net` extension. Vault stores credentials securely instead of hardcoding.

## 6) Notification Worker Architecture for This App

Two trigger patterns for the notification pipeline:

### Pattern A: Webhook-triggered (for immediate notifications)
- DB trigger on `booking_players` INSERT already enqueues rows in `notifications`.
- DB webhook on `notifications` INSERT invokes Edge Function immediately.
- Edge Function reads the inserted notification row and delivers via APNs or email.

### Pattern B: Cron-triggered (for scheduled reminders + retries)
- pg_cron invokes Edge Function every minute.
- Edge Function queries `notifications` where `status IN ('pending', 'failed') AND scheduled_for <= now()`.
- Processes batch, sends via APNs/email, updates status.

### Recommended approach for this app
Use **both patterns**:
- Webhook for instant delivery of `booking_created` and `booking_cancelled` notifications.
- Cron for `booking_reminder` notifications (scheduled 1 hour before game) and retrying failed deliveries.

## Important Constraints
- Edge Functions are designed for short-lived, idempotent operations.
- Cold starts are possible — design accordingly.
- Connect to Postgres via connection pools or serverless-friendly drivers.
- Webhook history is logged in the `net` schema.
