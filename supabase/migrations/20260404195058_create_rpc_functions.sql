-- Atomic booking creation (solves PostgREST single-transaction constraint)
create or replace function public.create_booking(
  p_starts_at timestamptz,
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

  insert into public.bookings (created_by, starts_at, ends_at)
  values (v_caller, p_starts_at, p_starts_at + interval '1 hour')
  returning id into v_booking_id;

  foreach v_player_id in array p_player_ids loop
    insert into public.booking_players (booking_id, player_id, added_by)
    values (v_booking_id, v_player_id, v_caller);
  end loop;

  return v_booking_id;
end;
$$;

revoke all on function public.create_booking(timestamptz, uuid[]) from public;
grant execute on function public.create_booking(timestamptz, uuid[]) to authenticated;

-- Invite code validation (callable pre-auth)
create or replace function public.validate_invite_code(p_code text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.invite_codes
    where code = trim(p_code) and is_active = true
  );
$$;

revoke all on function public.validate_invite_code(text) from public;
grant execute on function public.validate_invite_code(text) to anon, authenticated;
