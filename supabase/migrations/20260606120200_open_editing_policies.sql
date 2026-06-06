-- Open editing.
--
-- Any authenticated user can join a booking (add themselves), and any member of
-- a booking can add other players/guests or remove any participant. The deferred
-- assert_booking_players_constraints (creator must remain a player, 2-4 count)
-- provides the natural guard rails — you cannot empty a booking or remove its
-- creator. Cancelling the whole booking stays creator-only (unchanged).

begin;

-- Membership test as a SECURITY DEFINER helper.
-- NOTE: doing this inline as `exists (select 1 from booking_players bp where
-- bp.booking_id = booking_id ...)` is WRONG — inside that subquery the
-- unqualified `booking_id` binds to the inner `bp.booking_id`, collapsing the
-- correlation to `true` and letting a member of ANY booking edit ANY booking.
-- A helper with a named parameter avoids the name-shadowing trap entirely.
create or replace function public.is_booking_member(p_booking_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.booking_players
    where booking_id = p_booking_id
      and player_id = p_user_id
  );
$$;

revoke all on function public.is_booking_member(uuid, uuid) from public;
grant execute on function public.is_booking_member(uuid, uuid) to authenticated;

-- INSERT: self-join, or a member adding another real player / a guest.
drop policy if exists booking_players_insert_member on public.booking_players;

create policy booking_players_insert_open
  on public.booking_players
  for insert
  to authenticated
  with check (
    added_by = auth.uid()
    and exists (
      select 1 from public.bookings b
      where b.id = booking_id
        and b.status = 'active'
        and b.starts_at >= timezone('utc', now())
    )
    and (
      -- Self-join: add yourself as a real player.
      player_id = auth.uid()
      or
      -- A member can add another real player or a guest (player_id null).
      public.is_booking_member(booking_id, auth.uid())
    )
  );

-- DELETE: remove yourself, or (as a member) remove any participant incl. guests.
-- Restricted to active, still-upcoming bookings (matches the client and INSERT).
drop policy if exists booking_players_delete_self_or_creator on public.booking_players;

create policy booking_players_delete_member
  on public.booking_players
  for delete
  to authenticated
  using (
    exists (
      select 1 from public.bookings b
      where b.id = booking_id
        and b.status = 'active'
        and b.starts_at >= timezone('utc', now())
    )
    and (
      -- Remove yourself.
      player_id = auth.uid()
      or
      -- A member can remove any participant (including guests).
      public.is_booking_member(booking_id, auth.uid())
    )
  );

-- Bookings must only ever be created through the create_booking RPC, which
-- enforces overlap, operating hours, half-hour alignment and the 9 PM close.
-- Direct INSERTs (allowed by the old bookings_insert_own policy) bypassed all of
-- that, so remove them. create_booking is SECURITY DEFINER and is unaffected.
drop policy if exists bookings_insert_own on public.bookings;
revoke insert on public.bookings from authenticated;

commit;
