-- Open editing.
--
-- Any authenticated user can join a booking (add themselves), and any member of
-- a booking can add other players/guests or remove any participant. The deferred
-- assert_booking_players_constraints (creator must remain a player, 2-4 count)
-- provides the natural guard rails — you cannot empty a booking or remove its
-- creator. Cancelling the whole booking stays creator-only (unchanged).

begin;

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
      exists (
        select 1 from public.booking_players bp
        where bp.booking_id = booking_id
          and bp.player_id = auth.uid()
      )
    )
  );

-- DELETE: remove yourself, or (as a member) remove any participant incl. guests.
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
    )
    and (
      -- Remove yourself.
      player_id = auth.uid()
      or
      -- A member can remove any participant (including guests).
      exists (
        select 1 from public.booking_players bp
        where bp.booking_id = booking_id
          and bp.player_id = auth.uid()
      )
    )
  );

commit;
