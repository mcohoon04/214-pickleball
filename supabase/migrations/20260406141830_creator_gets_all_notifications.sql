-- Fix: booking creator now receives the same notifications as other players
-- Previously, "booking_created" push + email were skipped for the creator.
-- The reminder was already sent to everyone including creator.

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

  -- Reminder for every player (including creator)
  if coalesce(v_push_enabled, true) then
    insert into public.notifications (
      user_id, booking_id, type, channel, title, body, scheduled_for
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

  -- Booking created push for ALL players (including creator)
  if coalesce(v_push_enabled, true) then
    insert into public.notifications (
      user_id, booking_id, type, channel, title, body, scheduled_for
    )
    values (
      new.player_id,
      new.booking_id,
      'booking_created',
      'push',
      'New pickleball booking',
      format('%s booked a game at %s.', coalesce(v_actor_name, 'A player'), v_local_slot),
      timezone('utc', now())
    )
    on conflict do nothing;
  end if;

  -- Booking created email for ALL players (including creator)
  if coalesce(v_email_enabled, true) then
    insert into public.notifications (
      user_id, booking_id, type, channel, title, body, scheduled_for
    )
    values (
      new.player_id,
      new.booking_id,
      'booking_created',
      'email',
      'New pickleball booking',
      format('%s booked a game at %s.', coalesce(v_actor_name, 'A player'), v_local_slot),
      timezone('utc', now())
    )
    on conflict do nothing;
  end if;

  return new;
end;
$$;
