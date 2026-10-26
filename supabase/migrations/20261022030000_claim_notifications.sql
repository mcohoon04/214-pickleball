-- Atomic claiming for the send-notifications worker.
--
-- The worker used to SELECT due rows, then UPDATE them to 'processing' in a
-- second request. If a run died mid-batch, its rows stayed 'processing' forever
-- (2 reminders were stuck this way on 2026-10-20), and the two-step claim could
-- race with an overlapping run.
--
-- claim_notifications() claims due rows in one statement (FOR UPDATE SKIP
-- LOCKED, so overlapping runs never get the same row). It also reclaims rows a
-- dead run left 'processing' for longer than p_stale_after, which is well above
-- the Edge Function wall-clock limit (150s Free / 400s paid), so a live run
-- never loses its rows. A reclaim counts as a failed attempt, and a row on its
-- last attempt is marked failed instead, so a row that keeps killing the
-- worker can't loop forever.

create or replace function public.claim_notifications(
  p_limit integer default 10,
  p_stale_after interval default interval '10 minutes'
)
returns setof public.notifications
language plpgsql
set search_path = ''
as $$
begin
  -- Give up on rows abandoned by dead runs on their last attempt.
  update public.notifications
  set status = 'failed',
      retry_count = retry_count + 1,
      error_message = 'Abandoned by a crashed worker run'
  where status = 'processing'
    and updated_at < now() - p_stale_after
    and retry_count >= 2;

  return query
  with due as (
    select n.id
    from public.notifications n
    where n.scheduled_for <= now()
      and n.retry_count < 3
      and (
        n.status in ('pending', 'failed')
        or (n.status = 'processing' and n.updated_at < now() - p_stale_after)
      )
    order by n.scheduled_for
    limit p_limit
    for update skip locked
  )
  update public.notifications n
  set status = 'processing',
      retry_count = n.retry_count + case when n.status = 'processing' then 1 else 0 end
  from due
  where n.id = due.id
  returning n.*;
end;
$$;

revoke execute on function public.claim_notifications(integer, interval) from public, anon, authenticated;
grant execute on function public.claim_notifications(integer, interval) to service_role;

-- The stale-processing branch isn't covered by notifications_pending_queue_idx.
create index if not exists notifications_processing_updated_at_idx
  on public.notifications (updated_at)
  where status = 'processing';
