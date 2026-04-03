# Supabase Schema Design

## Scope
Schema for V1 with one shared court and <50 users. Core tables:
- `profiles` (extends `auth.users`)
- `bookings`
- `booking_players`
- `notifications`

This design uses queue-style notifications in Postgres and sends delivery through Supabase Edge Functions (APNs + email provider).

## Full SQL Migration
```sql
begin;

create extension if not exists "pgcrypto";

create type public.booking_status as enum ('active', 'cancelled');
create type public.notification_type as enum ('booking_created', 'booking_cancelled', 'booking_reminder');
create type public.notification_channel as enum ('push', 'email');
create type public.notification_status as enum ('pending', 'processing', 'sent', 'failed', 'skipped');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 50),
  avatar_url text,
  timezone text not null default 'America/Toronto',
  push_enabled boolean not null default true,
  email_enabled boolean not null default true,
  apns_device_token text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles (id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.booking_status not null default 'active',
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (ends_at = starts_at + interval '1 hour'),
  check (date_part('minute', starts_at) = 0 and date_part('second', starts_at) = 0),
  check (
    (status = 'active' and cancelled_at is null and cancelled_by is null)
    or
    (status = 'cancelled' and cancelled_at is not null and cancelled_by is not null)
  )
);

create table public.booking_players (
  booking_id uuid not null references public.bookings (id) on delete cascade,
  player_id uuid not null references public.profiles (id) on delete cascade,
  added_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (booking_id, player_id)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  booking_id uuid references public.bookings (id) on delete cascade,
  type public.notification_type not null,
  channel public.notification_channel not null,
  status public.notification_status not null default 'pending',
  title text not null,
  body text not null,
  scheduled_for timestamptz not null default timezone('utc', now()),
  sent_at timestamptz,
  provider_message_id text,
  provider_response jsonb,
  error_message text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create trigger bookings_set_updated_at
before update on public.bookings
for each row
execute function public.set_updated_at();

create trigger notifications_set_updated_at
before update on public.notifications
for each row
execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(new.email, '@', 1)
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

create or replace function public.enforce_booking_update_rules()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'cancelled' then
    raise exception 'Cancelled bookings are immutable';
  end if;

  if old.created_by <> auth.uid() then
    raise exception 'Only the booking creator can cancel this booking';
  end if;

  if new.created_by <> old.created_by
     or new.starts_at <> old.starts_at
     or new.ends_at <> old.ends_at then
    raise exception 'Only booking status can be changed';
  end if;

  if old.status = 'active' and new.status = 'cancelled' then
    new.cancelled_at := coalesce(new.cancelled_at, timezone('utc', now()));
    new.cancelled_by := coalesce(new.cancelled_by, auth.uid());
  elsif new.status <> old.status then
    raise exception 'Invalid booking status transition';
  end if;

  return new;
end;
$$;

create trigger bookings_enforce_update_rules
before update on public.bookings
for each row
execute function public.enforce_booking_update_rules();

create or replace function public.assert_booking_players_constraints()
returns trigger
language plpgsql
as $$
declare
  v_booking_id uuid;
  v_player_count integer;
  v_creator uuid;
begin
  v_booking_id := coalesce(new.booking_id, old.booking_id);

  select count(*) into v_player_count
  from public.booking_players
  where booking_id = v_booking_id;

  if v_player_count < 2 or v_player_count > 4 then
    raise exception 'A booking must have between 2 and 4 players';
  end if;

  select created_by into v_creator
  from public.bookings
  where id = v_booking_id;

  if not exists (
    select 1
    from public.booking_players bp
    where bp.booking_id = v_booking_id
      and bp.player_id = v_creator
  ) then
    raise exception 'Booking creator must be included as a player';
  end if;

  return null;
end;
$$;

create constraint trigger booking_players_size_and_creator_check
after insert or update or delete on public.booking_players
deferrable initially deferred
for each row
execute function public.assert_booking_players_constraints();

create or replace function public.enqueue_booking_notifications_on_player_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_actor_name text;
  v_push_enabled boolean;
  v_email_enabled boolean;
  v_local_slot text;
begin
  select * into v_booking
  from public.bookings
  where id = new.booking_id;

  if not found then
    return new;
  end if;

  select display_name into v_actor_name
  from public.profiles
  where id = new.added_by;

  select push_enabled, email_enabled
    into v_push_enabled, v_email_enabled
  from public.profiles
  where id = new.player_id;

  v_local_slot := to_char(
    v_booking.starts_at at time zone 'America/Toronto',
    'Dy, Mon DD at HH12:MI AM'
  );

  -- Reminder for every player in the booking (including creator).
  if coalesce(v_push_enabled, true) then
    insert into public.notifications (
      user_id,
      booking_id,
      type,
      channel,
      title,
      body,
      scheduled_for
    )
    values (
      new.player_id,
      new.booking_id,
      'booking_reminder',
      'push',
      'Pickleball reminder',
      format('Your game starts at %s.', v_local_slot),
      greatest(timezone('utc', now()), v_booking.starts_at - interval '1 hour')
    )
    on conflict do nothing;
  end if;

  -- "booking created" notice for invited players (not the creator).
  if new.player_id <> v_booking.created_by then
    if coalesce(v_push_enabled, true) then
      insert into public.notifications (
        user_id,
        booking_id,
        type,
        channel,
        title,
        body,
        scheduled_for
      )
      values (
        new.player_id,
        new.booking_id,
        'booking_created',
        'push',
        'New pickleball booking',
        format('%s added you to a game at %s.', coalesce(v_actor_name, 'A player'), v_local_slot),
        timezone('utc', now())
      )
      on conflict do nothing;
    end if;

    if coalesce(v_email_enabled, true) then
      insert into public.notifications (
        user_id,
        booking_id,
        type,
        channel,
        title,
        body,
        scheduled_for
      )
      values (
        new.player_id,
        new.booking_id,
        'booking_created',
        'email',
        'New pickleball booking',
        format('%s added you to a game at %s.', coalesce(v_actor_name, 'A player'), v_local_slot),
        timezone('utc', now())
      )
      on conflict do nothing;
    end if;
  end if;

  return new;
end;
$$;

create trigger booking_players_enqueue_notifications
after insert on public.booking_players
for each row
execute function public.enqueue_booking_notifications_on_player_insert();

create or replace function public.enqueue_booking_cancelled_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member record;
  v_local_slot text;
begin
  if not (old.status = 'active' and new.status = 'cancelled') then
    return new;
  end if;

  v_local_slot := to_char(
    new.starts_at at time zone 'America/Toronto',
    'Dy, Mon DD at HH12:MI AM'
  );

  for v_member in
    select bp.player_id, p.push_enabled, p.email_enabled
    from public.booking_players bp
    join public.profiles p on p.id = bp.player_id
    where bp.booking_id = new.id
  loop
    if v_member.player_id = coalesce(new.cancelled_by, auth.uid()) then
      continue;
    end if;

    if coalesce(v_member.push_enabled, true) then
      insert into public.notifications (
        user_id,
        booking_id,
        type,
        channel,
        title,
        body,
        scheduled_for
      )
      values (
        v_member.player_id,
        new.id,
        'booking_cancelled',
        'push',
        'Booking cancelled',
        format('A game at %s was cancelled.', v_local_slot),
        timezone('utc', now())
      )
      on conflict do nothing;
    end if;

    if coalesce(v_member.email_enabled, true) then
      insert into public.notifications (
        user_id,
        booking_id,
        type,
        channel,
        title,
        body,
        scheduled_for
      )
      values (
        v_member.player_id,
        new.id,
        'booking_cancelled',
        'email',
        'Booking cancelled',
        format('A game at %s was cancelled.', v_local_slot),
        timezone('utc', now())
      )
      on conflict do nothing;
    end if;
  end loop;

  return new;
end;
$$;

create trigger bookings_enqueue_cancel_notifications
after update of status on public.bookings
for each row
when (old.status is distinct from new.status)
execute function public.enqueue_booking_cancelled_notifications();

create or replace function public.list_players()
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.avatar_url
  from public.profiles p
  order by lower(p.display_name);
$$;

revoke all on function public.list_players() from public;
grant execute on function public.list_players() to authenticated;

create index profiles_display_name_idx
  on public.profiles (lower(display_name));

create index bookings_starts_at_idx
  on public.bookings (starts_at);

create index bookings_status_starts_at_idx
  on public.bookings (status, starts_at);

create index bookings_created_by_starts_at_idx
  on public.bookings (created_by, starts_at desc);

create unique index bookings_active_slot_uniq_idx
  on public.bookings (starts_at)
  where status = 'active';

create index booking_players_player_id_booking_id_idx
  on public.booking_players (player_id, booking_id);

create index notifications_user_created_at_idx
  on public.notifications (user_id, created_at desc);

create index notifications_pending_queue_idx
  on public.notifications (status, scheduled_for)
  where status in ('pending', 'failed');

create index notifications_booking_id_idx
  on public.notifications (booking_id);

create unique index notifications_event_dedupe_idx
  on public.notifications (user_id, booking_id, type, channel)
  where type in ('booking_created', 'booking_cancelled', 'booking_reminder');

alter table public.profiles enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_players enable row level security;
alter table public.notifications enable row level security;

create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy bookings_select_authenticated
  on public.bookings
  for select
  to authenticated
  using (true);

create policy bookings_insert_own
  on public.bookings
  for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and status = 'active'
    and starts_at >= timezone('utc', now())
    and cancelled_at is null
    and cancelled_by is null
  );

create policy bookings_update_creator
  on public.bookings
  for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

create policy booking_players_select_authenticated
  on public.booking_players
  for select
  to authenticated
  using (true);

create policy booking_players_insert_creator
  on public.booking_players
  for insert
  to authenticated
  with check (
    added_by = auth.uid()
    and exists (
      select 1
      from public.bookings b
      where b.id = booking_id
        and b.created_by = auth.uid()
        and b.status = 'active'
        and b.starts_at >= timezone('utc', now())
    )
  );

create policy booking_players_delete_creator
  on public.booking_players
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.bookings b
      where b.id = booking_id
        and b.created_by = auth.uid()
        and b.status = 'active'
    )
  );

create policy notifications_select_own
  on public.notifications
  for select
  to authenticated
  using (user_id = auth.uid());

-- Privileges for PostgREST callers.
grant select, update on public.profiles to authenticated;
grant select, insert, update on public.bookings to authenticated;
grant select, insert, delete on public.booking_players to authenticated;
grant select on public.notifications to authenticated;

revoke insert, delete on public.profiles from authenticated;
revoke insert, update, delete on public.notifications from authenticated;

-- Realtime publication for live calendar updates.
do $$
begin
  begin
    alter publication supabase_realtime add table public.bookings;
  exception
    when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.booking_players;
  exception
    when duplicate_object then null;
  end;
end
$$;

commit;
```

## RLS Summary
- `profiles`: users can read/update only their own row.
- `bookings`: any authenticated user can read shared schedule; only creator can insert/cancel their booking.
- `booking_players`: any authenticated user can read participant lists; only booking creator can add/remove players.
- `notifications`: users can read only their own notifications; writes are system-driven (triggers + Edge Functions with service role).

## Notification Delivery Model
- DB triggers insert rows into `notifications` with `status='pending'`.
- Edge Function worker polls pending rows where `scheduled_for <= now()`.
- Worker sends to APNs (push) or Resend/SendGrid (email), then updates `status`, `sent_at`, and provider metadata.

## Performance Notes
- `bookings_active_slot_uniq_idx` enforces one active booking per hourly slot.
- `bookings_status_starts_at_idx` and `bookings_starts_at_idx` support month/day schedule queries.
- `notifications_pending_queue_idx` supports efficient worker polling.
- `booking_players_player_id_booking_id_idx` speeds profile-centric booking lookups.
