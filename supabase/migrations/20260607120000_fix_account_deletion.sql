-- Fix in-app account deletion.
--
-- delete_account() could not actually delete a profile once the user had created
-- a booking or added a player, because of:
--   1. bookings.created_by  -> profiles  ON DELETE RESTRICT
--   2. booking_players.added_by -> profiles ON DELETE RESTRICT
--   3. the bookings CHECK requiring cancelled_by NOT NULL (cancelled_by is
--      SET NULL when the canceller's profile is deleted)
--   4. the deferred 2-4/creator constraint firing on the caller's now-cancelled
--      bookings (and on bookings dropping below 2 when the caller is removed).
--
-- Fix: make created_by/added_by nullable + SET NULL, relax the cancel CHECK,
-- skip the size/creator constraint on cancelled bookings, and rewrite
-- delete_account to be FK- and constraint-safe. The app only ever reads ACTIVE
-- bookings, which always keep a real creator; delete_account reassigns added_by
-- on surviving ACTIVE rows so the client never decodes a null created_by/added_by.

begin;

-- 1. Relax the two RESTRICT foreign keys to SET NULL.
alter table public.bookings alter column created_by drop not null;
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.bookings'::regclass and contype = 'f' and conname like '%created_by%'
  loop
    execute format('alter table public.bookings drop constraint %I', r.conname);
  end loop;
end $$;
alter table public.bookings
  add constraint bookings_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete set null;

alter table public.booking_players alter column added_by drop not null;
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.booking_players'::regclass and contype = 'f' and conname like '%added_by%'
  loop
    execute format('alter table public.booking_players drop constraint %I', r.conname);
  end loop;
end $$;
alter table public.booking_players
  add constraint booking_players_added_by_fkey
  foreign key (added_by) references public.profiles (id) on delete set null;

-- 2. Relax the bookings cancel CHECK so cancelled_by may be null (set null when
--    the canceller deletes their account). Match the unnamed check by definition.
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.bookings'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%cancelled_at%' and pg_get_constraintdef(oid) ilike '%cancelled_by%'
  loop
    execute format('alter table public.bookings drop constraint %I', r.conname);
  end loop;
end $$;
alter table public.bookings add constraint bookings_cancel_fields_chk
  check (
    (status = 'active' and cancelled_at is null and cancelled_by is null)
    or
    (status = 'cancelled' and cancelled_at is not null)
  );

-- 2b. The booking-update trigger blocks ALL updates on cancelled bookings, which
--     also blocks the FK ON DELETE SET NULL cascade (created_by/cancelled_by ->
--     null) fired when a profile is deleted. Allow that specific cleanup shape:
--     status/times unchanged and only created_by/cancelled_by being nulled.
--     Regular clients can't reach this (RLS WITH CHECK created_by = auth.uid()
--     forbids nulling created_by).
create or replace function public.enforce_booking_update_rules()
returns trigger
language plpgsql
as $$
begin
  -- Exactly the FK SET NULL shape: created_by and/or cancelled_by go from a
  -- value to NULL and EVERYTHING else is identical. (created_by can only reach
  -- this via the cascade — RLS WITH CHECK created_by = auth.uid() forbids a user
  -- nulling it; the only user-reachable case is nulling cancelled_by on their
  -- own already-cancelled booking, which is harmless.)
  if new.status = old.status
     and new.starts_at = old.starts_at
     and new.ends_at = old.ends_at
     and new.cancelled_at is not distinct from old.cancelled_at
     and new.created_at is not distinct from old.created_at
     and ((new.created_by is null and old.created_by is not null)
          or new.created_by is not distinct from old.created_by)
     and ((new.cancelled_by is null and old.cancelled_by is not null)
          or new.cancelled_by is not distinct from old.cancelled_by)
     and (new.created_by is distinct from old.created_by
          or new.cancelled_by is distinct from old.cancelled_by) then
    return new;  -- FK SET NULL cleanup from account deletion
  end if;

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

-- 3. The deferred size/creator constraint should not apply to cancelled bookings.
create or replace function public.assert_booking_players_constraints()
returns trigger
language plpgsql
as $$
declare
  v_booking_id uuid;
  v_player_count integer;
  v_creator uuid;
  v_status public.booking_status;
begin
  v_booking_id := coalesce(new.booking_id, old.booking_id);

  select status, created_by into v_status, v_creator
  from public.bookings
  where id = v_booking_id;

  if not found then
    return null;  -- parent booking deleted; constraint vacuously satisfied
  end if;

  if v_status = 'cancelled' then
    return null;  -- dead booking; player rules no longer apply
  end if;

  select count(*) into v_player_count
  from public.booking_players
  where booking_id = v_booking_id;

  if v_player_count < 2 or v_player_count > 4 then
    raise exception 'A booking must have between 2 and 4 players';
  end if;

  if not exists (
    select 1 from public.booking_players bp
    where bp.booking_id = v_booking_id and bp.player_id = v_creator
  ) then
    raise exception 'Booking creator must be included as a player';
  end if;

  return null;
end;
$$;

-- 4. FK- and constraint-safe account deletion.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  -- Cancel active bookings the caller created (others receive cancel notices).
  update public.bookings
    set status = 'cancelled',
        cancelled_at = timezone('utc', now()),
        cancelled_by = v_caller
    where created_by = v_caller and status = 'active';

  -- Delete other active bookings that can't survive losing the caller (< 2 left).
  -- (DELETE bypasses the creator-only update trigger and cascades players/notes.)
  delete from public.bookings b
    where b.status = 'active'
      and exists (
        select 1 from public.booking_players bp
        where bp.booking_id = b.id and bp.player_id = v_caller
      )
      and (
        select count(*) from public.booking_players bp2 where bp2.booking_id = b.id
      ) <= 2;

  -- Remove the caller from every remaining booking. Cancelled bookings skip the
  -- size/creator constraint; surviving active bookings keep >= 2 + their creator.
  delete from public.booking_players where player_id = v_caller;

  -- Keep added_by valid on surviving ACTIVE rows (the client reads these). Rows
  -- in cancelled bookings aren't read and are SET NULL when the profile is gone.
  update public.booking_players bp
    set added_by = b.created_by
    from public.bookings b
    where bp.booking_id = b.id
      and bp.added_by = v_caller
      and b.status = 'active'
      and b.created_by is not null
      and b.created_by <> v_caller;

  delete from public.notifications where user_id = v_caller;
  delete from public.profiles where id = v_caller;
  delete from auth.users where id = v_caller;
end;
$$;

revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;

commit;
