-- Allow players to remove THEMSELVES from a booking (not just creator)
drop policy if exists booking_players_delete_creator on public.booking_players;

create policy booking_players_delete_self_or_creator
  on public.booking_players
  for delete
  to authenticated
  using (
    -- You can remove yourself from any active booking you're in
    (player_id = auth.uid() and exists (
      select 1 from public.bookings b
      where b.id = booking_id
        and b.status = 'active'
    ))
    or
    -- Creator can remove anyone
    exists (
      select 1 from public.bookings b
      where b.id = booking_id
        and b.created_by = auth.uid()
        and b.status = 'active'
    )
  );

-- Allow any player in the booking to add new players (not just creator)
drop policy if exists booking_players_insert_creator on public.booking_players;

create policy booking_players_insert_member
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
        and (
          -- Creator can always add
          b.created_by = auth.uid()
          or
          -- Existing player in the booking can add
          exists (
            select 1 from public.booking_players bp
            where bp.booking_id = booking_id
              and bp.player_id = auth.uid()
          )
        )
    )
  );
