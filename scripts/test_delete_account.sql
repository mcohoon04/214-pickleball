-- Test harness for delete_account() (run against a DB with all migrations applied).
-- Seeds state directly as superuser (bypasses RLS; constraints still enforced),
-- runs delete_account() as Alice, and asserts the resulting state.
\set ON_ERROR_STOP on

-- Fixtures: 4 users.
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111','alice@t.com','{"full_name":"Alice"}'),
  ('22222222-2222-2222-2222-222222222222','bob@t.com','{"full_name":"Bob"}'),
  ('33333333-3333-3333-3333-333333333333','carol@t.com','{"full_name":"Carol"}'),
  ('44444444-4444-4444-4444-444444444444','dave@t.com','{"full_name":"Dave"}')
on conflict (id) do nothing;

create or replace function pg_temp.t(h int, m int default 0) returns timestamptz language sql as $$
  select (date_trunc('day', now() at time zone 'America/Toronto') + interval '1 day'
          + make_interval(hours => h, mins => m)) at time zone 'America/Toronto';
$$;

-- Booking AB_OWN: Alice's, active, 3 players, all added_by Alice.
-- Booking BOB4 : Bob's, active, 4 players; Carol & Dave were added by Alice.
-- Booking CAR2 : Carol's, active, 2 players (Carol, Alice).
-- Booking ACAN : Alice's, cancelled, 2 players (Alice, Dave), cancelled_by Alice.
insert into public.bookings (id, created_by, starts_at, ends_at, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111', pg_temp.t(10,0), pg_temp.t(10,30), 'active'),
  ('bbbbbbbb-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222', pg_temp.t(11,0), pg_temp.t(11,30), 'active'),
  ('cccccccc-0000-0000-0000-000000000003','33333333-3333-3333-3333-333333333333', pg_temp.t(12,0), pg_temp.t(12,30), 'active');
insert into public.bookings (id, created_by, starts_at, ends_at, status, cancelled_at, cancelled_by) values
  ('dddddddd-0000-0000-0000-000000000004','11111111-1111-1111-1111-111111111111', pg_temp.t(13,0), pg_temp.t(13,30), 'cancelled', now(), '11111111-1111-1111-1111-111111111111');

insert into public.booking_players (booking_id, player_id, added_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111'),
  ('aaaaaaaa-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222','22222222-2222-2222-2222-222222222222'),
  ('bbbbbbbb-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'),
  ('bbbbbbbb-0000-0000-0000-000000000002','33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-0000-0000-0000-000000000002','44444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111'),
  ('cccccccc-0000-0000-0000-000000000003','33333333-3333-3333-3333-333333333333','33333333-3333-3333-3333-333333333333'),
  ('cccccccc-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333'),
  ('dddddddd-0000-0000-0000-000000000004','11111111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111'),
  ('dddddddd-0000-0000-0000-000000000004','44444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111');

\echo '================ DELETE_ACCOUNT TEST ================'

-- Run delete_account as Alice. The commit forces the deferred constraints; if
-- delete_account were unsafe this would raise and ON_ERROR_STOP would abort.
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select public.delete_account();
commit;

do $$
declare ok boolean;
begin
  assert (select count(*) from public.profiles where id='11111111-1111-1111-1111-111111111111') = 0, 'profile not deleted';
  assert (select count(*) from auth.users where id='11111111-1111-1111-1111-111111111111') = 0, 'auth user not deleted';
  raise notice 'PASS: Alice profile + auth row deleted';

  assert (select status from public.bookings where id='aaaaaaaa-0000-0000-0000-000000000001')::text = 'cancelled', 'AB_OWN not cancelled';
  assert (select created_by from public.bookings where id='aaaaaaaa-0000-0000-0000-000000000001') is null, 'AB_OWN created_by not null';
  assert (select cancelled_by from public.bookings where id='aaaaaaaa-0000-0000-0000-000000000001') is null, 'AB_OWN cancelled_by not null';
  raise notice 'PASS: Alice''s own booking cancelled, created_by/cancelled_by SET NULL';

  assert (select status from public.bookings where id='bbbbbbbb-0000-0000-0000-000000000002')::text = 'active', 'BOB4 should stay active';
  assert (select count(*) from public.booking_players where booking_id='bbbbbbbb-0000-0000-0000-000000000002') = 3, 'BOB4 should have 3 players';
  assert (select count(*) from public.booking_players where booking_id='bbbbbbbb-0000-0000-0000-000000000002' and player_id='11111111-1111-1111-1111-111111111111') = 0, 'Alice not removed from BOB4';
  assert (select count(*) from public.booking_players where booking_id='bbbbbbbb-0000-0000-0000-000000000002' and added_by='22222222-2222-2222-2222-222222222222') = 3, 'BOB4 added_by not reassigned to creator';
  raise notice 'PASS: others 4-player booking kept Alice removed (3 left), added_by reassigned to creator';

  assert (select count(*) from public.bookings where id='cccccccc-0000-0000-0000-000000000003') = 0, 'CAR2 should be deleted (would drop below 2)';
  assert (select count(*) from public.booking_players where booking_id='cccccccc-0000-0000-0000-000000000003') = 0, 'CAR2 players should be gone';
  raise notice 'PASS: others 2-player booking deleted (cascade)';

  assert (select created_by from public.bookings where id='dddddddd-0000-0000-0000-000000000004') is null, 'cancelled booking created_by not null';
  assert (select cancelled_by from public.bookings where id='dddddddd-0000-0000-0000-000000000004') is null, 'cancelled booking cancelled_by not null';
  raise notice 'PASS: pre-cancelled booking survived with created_by/cancelled_by SET NULL';

  -- CRITICAL app-safety invariant: the client only reads ACTIVE bookings and
  -- decodes added_by as a non-optional UUID.
  assert (select count(*) from public.booking_players bp join public.bookings b on b.id=bp.booking_id
          where b.status='active' and bp.added_by is null) = 0, 'an ACTIVE booking has a null added_by';
  raise notice 'PASS: no ACTIVE booking has a null added_by (client-safe)';
end $$;

\echo '================ END ================'
