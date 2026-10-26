-- Local test harness for public.claim_notifications (notification queue claiming).
-- Run against a local DB with all migrations applied:
--   psql "$LOCAL_DB_URL" -f scripts/test_claim_notifications.sql   (as a superuser, e.g.
--   supabase_admin: scenario 9 opens a second session via dblink)
--
-- Each scenario runs in its own begin;...rollback; so nothing persists (re-runnable).
-- PASS lines print as NOTICEs; the first failure raises and psql exits non-zero.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'alice@test.com', '{"full_name":"Alice"}')
on conflict (id) do nothing;

-- Clear rows a previously aborted run may have committed (scenario 9 commits).
delete from public.notifications where user_id = '11111111-1111-1111-1111-111111111111';

-- Insert one queue row; returns its id. Ages are relative to now().
create or replace function pg_temp.n(
  p_status public.notification_status,
  p_due interval default interval '1 minute',      -- scheduled this long ago (negative = future)
  p_retry int default 0,
  p_touched interval default interval '0 minutes' -- updated_at this long ago
) returns uuid language sql as $$
  insert into public.notifications (user_id, type, channel, status, title, body, scheduled_for, retry_count, updated_at)
  values ('11111111-1111-1111-1111-111111111111', 'booking_created', 'push', p_status,
          't', 'b', now() - p_due, p_retry, now() - p_touched)
  returning id;
$$;

create or replace function pg_temp.check(p_name text, p_ok boolean) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then
    raise exception 'FAIL %', p_name;
  end if;
  raise notice 'PASS %', p_name;
end;
$$;

\echo '================ CLAIM NOTIFICATIONS TESTS ================'

-- 1. Due pending row is claimed -> processing, retry_count unchanged.
begin;
select pg_temp.n('pending') as id \gset
select count(*) = 1 as ok from public.claim_notifications(10) c where c.id = :'id' \gset
select pg_temp.check('due pending row is claimed', :'ok'::boolean);
select pg_temp.check('claimed row is processing with retry 0',
  (select status = 'processing' and retry_count = 0 from public.notifications where id = :'id'));
rollback;

-- 2. Future row is not claimed.
begin;
select pg_temp.n('pending', interval '-5 minutes') as id \gset
select pg_temp.check('future row is not claimed',
  not exists (select 1 from public.claim_notifications(10) c where c.id = :'id'));
rollback;

-- 3. Failed rows are retried until retry_count reaches 3.
begin;
select pg_temp.n('failed', p_retry => 2) as retryable \gset
select pg_temp.n('failed', p_retry => 3) as exhausted \gset
create temp table claimed on commit drop as select id from public.claim_notifications(10);
select pg_temp.check('failed row with retry 2 is claimed', exists (select 1 from claimed where id = :'retryable'));
select pg_temp.check('failed row with retry 3 is not claimed', not exists (select 1 from claimed where id = :'exhausted'));
rollback;

-- 4. Fresh processing row (live run) is not claimed.
begin;
select pg_temp.n('processing', p_touched => interval '2 minutes') as id \gset
select pg_temp.check('fresh processing row is not claimed',
  not exists (select 1 from public.claim_notifications(10) c where c.id = :'id'));
select pg_temp.check('fresh processing row is untouched',
  (select status = 'processing' and retry_count = 0 from public.notifications where id = :'id'));
rollback;

-- 5. Stale processing row (dead run) is reclaimed and the lost attempt is counted.
begin;
select pg_temp.n('processing', p_touched => interval '15 minutes') as id \gset
select pg_temp.check('stale processing row is reclaimed',
  exists (select 1 from public.claim_notifications(10) c where c.id = :'id'));
select pg_temp.check('reclaim counts an attempt (retry 0 -> 1)',
  (select status = 'processing' and retry_count = 1 from public.notifications where id = :'id'));
rollback;

-- 6. A row that keeps killing runs is given up on instead of looping forever.
begin;
select pg_temp.n('processing', p_retry => 2, p_touched => interval '15 minutes') as id \gset
select pg_temp.check('stale processing row on its last attempt is not reclaimed',
  not exists (select 1 from public.claim_notifications(10) c where c.id = :'id'));
select pg_temp.check('...and is marked failed with retry 3',
  (select status = 'failed' and retry_count = 3 and error_message is not null
     from public.notifications where id = :'id'));
rollback;

-- 7. Terminal rows are never claimed.
begin;
select pg_temp.n('sent') as sent_id \gset
select pg_temp.n('skipped') as skipped_id \gset
create temp table claimed on commit drop as select id from public.claim_notifications(10);
select pg_temp.check('sent and skipped rows are not claimed',
  not exists (select 1 from claimed where id in (:'sent_id', :'skipped_id')));
rollback;

-- 8. Limit is respected, oldest due first; a second call does not re-claim them.
begin;
select pg_temp.n('pending', interval '3 minutes') as oldest \gset
select pg_temp.n('pending', interval '2 minutes') as middle \gset
select pg_temp.n('pending', interval '1 minute')  as newest \gset
create temp table first_claim on commit drop as select id from public.claim_notifications(2);
select pg_temp.check('limit 2 claims exactly 2 rows', (select count(*) = 2 from first_claim));
select pg_temp.check('oldest due rows are claimed first',
  exists (select 1 from first_claim where id = :'oldest')
  and exists (select 1 from first_claim where id = :'middle'));
create temp table second_claim on commit drop as select id from public.claim_notifications(10);
select pg_temp.check('second call only gets the remaining row',
  (select count(*) = 1 from second_claim)
  and exists (select 1 from second_claim where id = :'newest'));
rollback;

-- 9. Overlapping runs: a row locked by another run's claim is skipped, not waited on.
--    Fixtures are committed so the second session (dblink) can see them; that
--    session has a 3s statement_timeout, so a missing SKIP LOCKED fails instead of hanging.
create extension if not exists dblink;
select pg_temp.n('pending', interval '2 minutes') as locked_id \gset
select pg_temp.n('pending', interval '1 minute') as free_id \gset
begin;
select 1 from public.notifications where id = :'locked_id' for update;
select pg_temp.check('concurrent claim skips the locked row and takes the free one',
  (select array_agg(id::text) from dblink(
     'host=localhost dbname=postgres user=postgres options=''-c statement_timeout=3000''',
     'select id from public.claim_notifications(10)') as t(id uuid)) = array[:'free_id']);
rollback;
delete from public.notifications where id in (:'locked_id', :'free_id');

-- 10. Only the service role may call it.
select pg_temp.check('anon cannot execute',
  not has_function_privilege('anon', 'public.claim_notifications(integer, interval)', 'execute'));
select pg_temp.check('authenticated cannot execute',
  not has_function_privilege('authenticated', 'public.claim_notifications(integer, interval)', 'execute'));
select pg_temp.check('service_role can execute',
  has_function_privilege('service_role', 'public.claim_notifications(integer, interval)', 'execute'));

\echo '================ DONE ================'
