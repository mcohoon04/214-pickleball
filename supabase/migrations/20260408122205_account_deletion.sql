-- Account deletion RPC
-- Cancels all bookings created by the user, removes them from other bookings,
-- deletes their profile, and deletes their auth.users row.

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

  -- Cancel all bookings created by this user
  update public.bookings
  set status = 'cancelled',
      cancelled_at = timezone('utc', now()),
      cancelled_by = v_caller
  where created_by = v_caller
    and status = 'active';

  -- Remove user from other people's bookings
  delete from public.booking_players
  where player_id = v_caller;

  -- Delete notifications for this user
  delete from public.notifications
  where user_id = v_caller;

  -- Delete profile
  delete from public.profiles
  where id = v_caller;

  -- Delete the auth user (requires security definer)
  delete from auth.users
  where id = v_caller;
end;
$$;

revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;
