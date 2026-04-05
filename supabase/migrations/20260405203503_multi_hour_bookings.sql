-- Multi-hour bookings: remove 1-hour constraint, add overlap detection

-- 1. Drop the 1-hour enforcement constraint
alter table public.bookings drop constraint if exists bookings_ends_at_check;
-- The constraint might have a generated name, so also try:
alter table public.bookings drop constraint if exists bookings_check;

-- Remove all check constraints and re-add the ones we want to keep
-- First, find and drop the ends_at = starts_at + interval '1 hour' constraint
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%ends_at = %starts_at%1 hour%'
  loop
    execute format('alter table public.bookings drop constraint %I', r.conname);
  end loop;
end;
$$;

-- 2. Add new constraints for multi-hour bookings
-- ends_at must be after starts_at
alter table public.bookings add constraint bookings_ends_after_starts
  check (ends_at > starts_at);

-- ends_at must be on the hour
alter table public.bookings add constraint bookings_ends_at_on_hour
  check (date_part('minute', ends_at) = 0 and date_part('second', ends_at) = 0);

-- Max booking duration: 4 hours
alter table public.bookings add constraint bookings_max_duration
  check (ends_at <= starts_at + interval '4 hours');

-- 3. Drop the old unique index (only prevented same starts_at)
drop index if exists public.bookings_active_slot_uniq_idx;

-- 4. Update create_booking RPC to accept end time and check overlaps
create or replace function public.create_booking(
  p_starts_at timestamptz,
  p_ends_at timestamptz,
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
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  if array_length(p_player_ids, 1) is null
     or array_length(p_player_ids, 1) < 2
     or array_length(p_player_ids, 1) > 4 then
    raise exception 'Must have between 2 and 4 players';
  end if;

  if not (v_caller = any(p_player_ids)) then
    raise exception 'Booking creator must be included as a player';
  end if;

  if (select count(distinct x) from unnest(p_player_ids) x) <> array_length(p_player_ids, 1) then
    raise exception 'Duplicate player IDs not allowed';
  end if;

  if p_starts_at < timezone('utc', now()) then
    raise exception 'Cannot book in the past';
  end if;

  if date_part('hour', p_starts_at at time zone 'America/Toronto') not between 5 and 20 then
    raise exception 'Bookings allowed between 5 AM and 9 PM only';
  end if;

  if date_part('minute', p_starts_at) <> 0 or date_part('second', p_starts_at) <> 0 then
    raise exception 'Bookings must start on the hour';
  end if;

  if p_ends_at <= p_starts_at then
    raise exception 'End time must be after start time';
  end if;

  if date_part('minute', p_ends_at) <> 0 or date_part('second', p_ends_at) <> 0 then
    raise exception 'End time must be on the hour';
  end if;

  if p_ends_at > p_starts_at + interval '4 hours' then
    raise exception 'Maximum booking duration is 4 hours';
  end if;

  -- Check for overlapping active bookings
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

  return v_booking_id;
end;
$$;

-- Update grants (signature changed - 3 params now)
revoke all on function public.create_booking(timestamptz, timestamptz, uuid[]) from public;
grant execute on function public.create_booking(timestamptz, timestamptz, uuid[]) to authenticated;

-- Drop old 2-param version if it exists
drop function if exists public.create_booking(timestamptz, uuid[]);
