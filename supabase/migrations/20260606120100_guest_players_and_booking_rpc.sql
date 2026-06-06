-- Guest players.
--
-- A booking participant may now be a "guest": someone who is NOT a real user
-- (no profile, no login). Guests are stored as booking_players rows with
-- player_id = NULL and guest_name set. The booking creator must still be a
-- real user, and total participants stay capped at 4.

begin;

-- ============================================================
-- 1. booking_players gets a surrogate primary key + guest columns.
--    Old PK was composite (booking_id, player_id), which cannot represent
--    multiple guests (NULL player_id) in the same booking.
-- ============================================================
alter table public.booking_players drop constraint booking_players_pkey;
alter table public.booking_players add column id uuid not null default gen_random_uuid();
alter table public.booking_players add primary key (id);

alter table public.booking_players alter column player_id drop not null;
alter table public.booking_players add column guest_name text;

-- Exactly one of (player_id, guest_name) is set.
alter table public.booking_players add constraint booking_players_user_xor_guest
  check (
    (player_id is not null and guest_name is null)
    or
    (player_id is null and guest_name is not null and char_length(trim(guest_name)) between 1 and 50)
  );

-- Keep the no-duplicate-real-player guarantee (guests are allowed to repeat).
create unique index booking_players_unique_real_player
  on public.booking_players (booking_id, player_id)
  where player_id is not null;

-- ============================================================
-- 2. Notification enqueue trigger must skip guest rows.
--    (The cancelled-notifications trigger already INNER JOINs profiles, so
--     guest rows are naturally excluded there.)
-- ============================================================
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
  v_created_body text;
begin
  -- Guests have no profile/email/device token — nothing to enqueue.
  if new.player_id is null then
    return new;
  end if;

  select * into v_booking from public.bookings where id = new.booking_id;
  if not found then
    return new;
  end if;

  select display_name into v_actor_name from public.profiles where id = new.added_by;

  select push_enabled, email_enabled
    into v_push_enabled, v_email_enabled
  from public.profiles where id = new.player_id;

  v_local_slot := to_char(
    v_booking.starts_at at time zone 'America/Toronto',
    'Dy, Mon DD at HH12:MI AM'
  );

  -- Self-join / creator-adds-self reads as a confirmation; otherwise it's an invite.
  if new.player_id = new.added_by then
    v_created_body := format('Your game is booked for %s.', v_local_slot);
  else
    v_created_body := format('%s added you to a game at %s.', coalesce(v_actor_name, 'A player'), v_local_slot);
  end if;

  -- Reminder for every player (including creator).
  if coalesce(v_push_enabled, true) then
    insert into public.notifications (user_id, booking_id, type, channel, title, body, scheduled_for)
    values (
      new.player_id, new.booking_id, 'booking_reminder', 'push', 'Pickleball reminder',
      format('Your game starts at %s.', v_local_slot),
      greatest(timezone('utc', now()), v_booking.starts_at - interval '1 hour')
    )
    on conflict do nothing;
  end if;

  -- Booking-created push for all players (including creator).
  if coalesce(v_push_enabled, true) then
    insert into public.notifications (user_id, booking_id, type, channel, title, body, scheduled_for)
    values (
      new.player_id, new.booking_id, 'booking_created', 'push', 'New pickleball booking',
      v_created_body,
      timezone('utc', now())
    )
    on conflict do nothing;
  end if;

  -- Booking-created email for all players (including creator).
  if coalesce(v_email_enabled, true) then
    insert into public.notifications (user_id, booking_id, type, channel, title, body, scheduled_for)
    values (
      new.player_id, new.booking_id, 'booking_created', 'email', 'New pickleball booking',
      v_created_body,
      timezone('utc', now())
    )
    on conflict do nothing;
  end if;

  return new;
end;
$$;

-- ============================================================
-- 3. create_booking: half-hour slots + guest players.
--    Replaces the 3-arg version with a 4-arg version (p_guest_names defaulted,
--    so existing 3-arg-style PostgREST calls still resolve).
-- ============================================================
drop function if exists public.create_booking(timestamptz, timestamptz, uuid[]);

create or replace function public.create_booking(
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_player_ids uuid[],
  p_guest_names text[] default '{}'
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
  v_guest_name text;
  v_clean_guest text;
  v_real integer := coalesce(array_length(p_player_ids, 1), 0);
  v_guests integer := coalesce(array_length(p_guest_names, 1), 0);
  v_total integer;
  v_close timestamptz;
begin
  v_total := v_real + v_guests;

  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  if v_total < 2 or v_total > 4 then
    raise exception 'A booking must have between 2 and 4 players';
  end if;

  -- The creator must be a real player in the booking.
  if v_real < 1 or not (v_caller = any(p_player_ids)) then
    raise exception 'Booking creator must be included as a player';
  end if;

  if (select count(distinct x) from unnest(p_player_ids) x) <> v_real then
    raise exception 'Duplicate player IDs not allowed';
  end if;

  if p_starts_at < timezone('utc', now()) then
    raise exception 'Cannot book in the past';
  end if;

  if date_part('hour', p_starts_at at time zone 'America/Toronto') not between 5 and 20 then
    raise exception 'Bookings allowed between 5 AM and 9 PM only';
  end if;

  if date_part('minute', p_starts_at) not in (0, 30) or date_part('second', p_starts_at) <> 0 then
    raise exception 'Bookings must start on the hour or half hour';
  end if;

  if p_ends_at <= p_starts_at then
    raise exception 'End time must be after start time';
  end if;

  if date_part('minute', p_ends_at) not in (0, 30) or date_part('second', p_ends_at) <> 0 then
    raise exception 'End time must be on the hour or half hour';
  end if;

  if p_ends_at > p_starts_at + interval '4 hours' then
    raise exception 'Maximum booking duration is 4 hours';
  end if;

  -- Must end by 9 PM Toronto on the start day (DST/midnight-safe).
  v_close := (date_trunc('day', p_starts_at at time zone 'America/Toronto') + interval '21 hours')
             at time zone 'America/Toronto';
  if p_ends_at > v_close then
    raise exception 'Bookings must end by 9 PM';
  end if;

  -- Overlap with another active booking.
  if exists (
    select 1 from public.bookings
    where status = 'active'
      and starts_at < p_ends_at
      and ends_at > p_starts_at
  ) then
    raise exception 'Time slot conflicts with an existing booking';
  end if;

  insert into public.bookings (created_by, starts_at, ends_at)
  values (v_caller, p_starts_at, p_ends_at)
  returning id into v_booking_id;

  foreach v_player_id in array p_player_ids loop
    insert into public.booking_players (booking_id, player_id, added_by)
    values (v_booking_id, v_player_id, v_caller);
  end loop;

  if v_guests > 0 then
    foreach v_guest_name in array p_guest_names loop
      v_clean_guest := nullif(left(trim(coalesce(v_guest_name, '')), 50), '');
      insert into public.booking_players (booking_id, player_id, guest_name, added_by)
      values (v_booking_id, null, coalesce(v_clean_guest, 'Guest'), v_caller);
    end loop;
  end if;

  return v_booking_id;
end;
$$;

revoke all on function public.create_booking(timestamptz, timestamptz, uuid[], text[]) from public;
grant execute on function public.create_booking(timestamptz, timestamptz, uuid[], text[]) to authenticated;

commit;
