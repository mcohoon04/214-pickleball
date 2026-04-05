# Supabase CLI & Local Development Research

## Scope
CLI installation, local development workflow, migrations, Edge Function development, and deployment.

## Primary Sources
- CLI getting started:
  - https://supabase.com/docs/guides/local-development/cli/getting-started
- Local development with migrations:
  - https://supabase.com/docs/guides/local-development/overview
- CLI reference:
  - https://supabase.com/docs/reference/cli/introduction

## 1) Installation

### macOS (Homebrew)
```bash
brew install supabase/tap/supabase
brew upgrade supabase  # update
```

### npm (dev dependency)
```bash
npm install supabase --save-dev
npx supabase --help
```

Global `npm install -g supabase` is **not supported**.

### Requirements
- Node.js 20+ (for npx/npm)
- Docker Desktop (or Podman, Rancher Desktop, OrbStack, colima)

## 2) Project Initialization

```bash
supabase init
```

Creates `supabase/` directory with `config.toml`.

### Linking to remote project
```bash
supabase login
supabase link --project-ref <project-id>
supabase db pull          # pulls remote schema as migration
```

## 3) Local Development Stack

### Start all services
```bash
supabase start
```

Spins up Docker containers for: Postgres, Auth (GoTrue), Realtime, Storage, PostgREST, Studio, Mailpit.

### Local endpoints
| Service | URL |
|---------|-----|
| API Gateway | `http://localhost:54321` |
| REST (PostgREST) | `http://localhost:54321/rest/v1/` |
| Realtime | `http://localhost:54321/realtime/v1/` |
| Storage | `http://localhost:54321/storage/v1/` |
| Auth (GoTrue) | `http://localhost:54321/auth/v1/` |
| Studio UI | `http://localhost:54323` |
| PostgreSQL | `postgresql://postgres:postgres@localhost:54322/postgres` |
| Mailpit (email) | `http://localhost:54324` |

### Stop services
```bash
supabase stop              # preserves data
supabase stop --no-backup  # permanently deletes local data
```

### Check status
```bash
supabase status   # shows URLs, keys, service status
```

## 4) Database Migrations

### Create a new migration
```bash
supabase migration new create_bookings_table
```

Creates timestamped file in `supabase/migrations/`.

### Write SQL in migration file
```sql
create table public.bookings (
    id uuid primary key default gen_random_uuid(),
    created_by uuid not null,
    starts_at timestamptz not null,
    ends_at timestamptz not null
);
```

### Apply migrations locally
```bash
supabase db reset   # resets DB, runs all migrations + seed.sql
```

### Push migrations to remote
```bash
supabase db push
```

### Other migration commands
```bash
supabase migration list       # show migration status
supabase migration up         # apply pending migrations
supabase migration squash     # consolidate multiple migrations
supabase migration repair     # sync migration history
supabase db diff --schema public  # view schema differences
supabase db diff -f my_schema     # capture diff as migration file
supabase db lint              # check for schema errors
```

## 5) Seed Data

Create `supabase/seed.sql`:
```sql
insert into public.profiles (id, display_name)
values
  ('00000000-0000-0000-0000-000000000001', 'Test User 1'),
  ('00000000-0000-0000-0000-000000000002', 'Test User 2');
```

`supabase db reset` applies migrations then seed data.

## 6) Edge Functions Local Dev

### Serve locally
```bash
supabase functions serve                        # all functions
supabase functions serve my-func                # one function
supabase functions serve --env-file .env.local  # with secrets
```

### Deploy to remote
```bash
supabase functions deploy my-function
supabase functions deploy my-function --no-verify-jwt
```

### Manage functions
```bash
supabase functions new my-function     # create boilerplate
supabase functions list                # list deployed functions
supabase functions delete my-function  # remove
```

## 7) Secrets

### Remote (production)
```bash
supabase secrets set MY_KEY=my_value
supabase secrets set --env-file .env
supabase secrets list
supabase secrets unset MY_KEY
```

### Local
Place secrets in `supabase/functions/.env` (auto-loaded) or use `--env-file` flag.

## 8) Type Generation

```bash
supabase gen types typescript --local > types/supabase.ts
supabase gen types swift --local       # Swift types
```

## 9) Environment Configuration

`supabase/config.toml` controls local settings. Example auth config:
```toml
[auth.external.google]
enabled = true
client_id = "env(GOOGLE_CLIENT_ID)"
secret = "env(GOOGLE_CLIENT_SECRET)"
```

Store sensitive values in `.env`:
```
GOOGLE_CLIENT_ID="redacted"
GOOGLE_CLIENT_SECRET="redacted"
```

Changes to `config.toml` require `supabase stop && supabase start`.

## 10) Workflow Summary for This App

```
1. supabase init
2. supabase link --project-ref <ref>
3. supabase migration new initial_schema
4. (paste schema SQL from supabase-schema-design.md)
5. supabase db reset (test locally)
6. supabase functions new send-notifications
7. (implement Edge Function)
8. supabase functions serve --env-file .env.local (test)
9. supabase db push (deploy schema to remote)
10. supabase functions deploy send-notifications
11. supabase secrets set --env-file .env (deploy secrets)
```
