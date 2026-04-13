-- Fix: assert_booking_players_constraints incorrectly raised when a booking
-- was hard-deleted, because the ON DELETE CASCADE on booking_players fires
-- the deferred trigger with old.booking_id pointing at a booking that no
-- longer exists. The count-of-zero check then failed.
--
-- Fix: if the parent booking has been deleted, the constraint is vacuously
-- satisfied — return early without raising.

create or replace function public.assert_booking_players_constraints()
returns trigger
language plpgsql
as $$
declare
  v_booking_id uuid;
  v_player_count integer;
  v_creator uuid;
  v_booking_exists boolean;
begin
  v_booking_id := coalesce(new.booking_id, old.booking_id);

  select exists (select 1 from public.bookings where id = v_booking_id)
    into v_booking_exists;

  if not v_booking_exists then
    return null;
  end if;

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
