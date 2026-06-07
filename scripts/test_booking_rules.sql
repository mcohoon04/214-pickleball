-- Local test harness for the booking-rules changes (half-hour, guests, open editing).
-- Run against a freshly reset local Supabase DB:
--   supabase db reset
--   psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=0 -f scripts/test_booking_rules.sql
--
-- Each scenario runs in its own begin;...rollback; so nothing persists (re-runnable).
-- Expected-failure scenarios catch the error inside a plpgsql block (savepoint),
-- so the outer transaction is not aborted. PASS/FAIL lines print as NOTICEs.

\set ON_ERROR_STOP off

-- ---------------------------------------------------------------------------
-- Fixtures (committed once for the session): 3 users + a time helper.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.com', '{"full_name":"Alice"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.com',   '{"full_name":"Bob"}'),
  ('33333333-3333-3333-3333-333333333333', 'carol@test.com', '{"full_name":"Carol"}')
on conflict (id) do nothing;

-- timestamptz for tomorrow at H:M Toronto time
create or replace function pg_temp.t(h int, m int default 0) returns timestamptz language sql as $$
  select (date_trunc('day', now() at time zone 'America/Toronto') + interval '1 day'
          + make_interval(hours => h, mins => m)) at time zone 'America/Toronto';
$$;

\echo '================ BOOKING RULES TESTS ================'

-- ---------------------------------------------------------------------------
-- 1. Happy path: 30-minute booking, two real players.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
declare v_b uuid; v_cnt int;
begin
  v_b := public.create_booking(pg_temp.t(10,0), pg_temp.t(10,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  select count(*) into v_cnt from public.booking_players where booking_id = v_b;
  assert v_cnt = 2, format('expected 2 players, got %s', v_cnt);
  assert (select ends_at - starts_at from public.bookings where id = v_b) = interval '30 minutes', 'expected 30-min duration';
  raise notice 'PASS 1: 30-minute booking created with 2 players';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 2. Half-hour START (10:30 -> 11:30).
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
declare v_b uuid;
begin
  v_b := public.create_booking(pg_temp.t(10,30), pg_temp.t(11,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  assert v_b is not null, 'booking should be created';
  raise notice 'PASS 2: booking starting on the half hour (10:30) created';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 3. Guests: creator + 3 guests (no cap on guests, total = 4).
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
declare v_b uuid; v_total int; v_guests int; v_real int;
begin
  v_b := public.create_booking(pg_temp.t(12,0), pg_temp.t(13,0),
                               array['11111111-1111-1111-1111-111111111111'::uuid],
                               array['Dave','Owen','Carl']);
  select count(*) into v_total from public.booking_players where booking_id = v_b;
  select count(*) into v_guests from public.booking_players where booking_id = v_b and player_id is null;
  select count(*) into v_real from public.booking_players where booking_id = v_b and player_id is not null;
  assert v_total = 4, format('expected 4 total, got %s', v_total);
  assert v_guests = 3, format('expected 3 guests, got %s', v_guests);
  assert v_real = 1, format('expected 1 real (creator), got %s', v_real);
  assert (select guest_name from public.booking_players where booking_id = v_b and guest_name = 'Dave') = 'Dave', 'guest name Dave missing';
  raise notice 'PASS 3: creator + 3 guests (no guest cap)';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 4. Unnamed guest -> stored as 'Guest'.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
declare v_b uuid; v_name text;
begin
  v_b := public.create_booking(pg_temp.t(14,0), pg_temp.t(14,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid],
                               array['   ']);  -- blank name
  select guest_name into v_name from public.booking_players where booking_id = v_b and player_id is null;
  assert v_name = 'Guest', format('expected ''Guest'', got %L', v_name);
  raise notice 'PASS 4: blank guest name normalized to ''Guest''';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 5. Reject :15 start.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
begin
  begin
    perform public.create_booking(pg_temp.t(10,15), pg_temp.t(10,45),
                                  array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
    raise exception 'TESTFAIL: :15 start should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 5: :15 start rejected (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 6. End after 9 PM rejected; 8:30->9:00 PM allowed.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
declare v_b uuid;
begin
  -- Allowed: 20:30 -> 21:00
  v_b := public.create_booking(pg_temp.t(20,30), pg_temp.t(21,0),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  assert v_b is not null, '20:30->21:00 should be allowed';
  raise notice 'PASS 6a: 8:30 PM -> 9:00 PM allowed';

  begin
    perform public.create_booking(pg_temp.t(20,30), pg_temp.t(21,30),
                                  array['11111111-1111-1111-1111-111111111111'::uuid,'33333333-3333-3333-3333-333333333333'::uuid]);
    raise exception 'TESTFAIL: end after 9 PM should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 6b: end after 9 PM rejected (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 7. Over 4 hours rejected.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
begin
  begin
    perform public.create_booking(pg_temp.t(10,0), pg_temp.t(15,0),
                                  array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
    raise exception 'TESTFAIL: >4h should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 7: >4h booking rejected (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 8. Creator must be a player.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
begin
  begin
    perform public.create_booking(pg_temp.t(11,0), pg_temp.t(11,30),
                                  array['22222222-2222-2222-2222-222222222222'::uuid,'33333333-3333-3333-3333-333333333333'::uuid]);
    raise exception 'TESTFAIL: creator-not-in-players should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 8: creator-not-in-players rejected (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 9. Fewer than 2 / more than 4 total rejected.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
begin
  begin
    perform public.create_booking(pg_temp.t(11,0), pg_temp.t(11,30),
                                  array['11111111-1111-1111-1111-111111111111'::uuid]);
    raise exception 'TESTFAIL: single player should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 9a: <2 players rejected (%)', sqlerrm;
  end;

  begin
    perform public.create_booking(pg_temp.t(11,0), pg_temp.t(11,30),
                                  array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid,'33333333-3333-3333-3333-333333333333'::uuid],
                                  array['G1','G2']);
    raise exception 'TESTFAIL: 5 total should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 9b: >4 total (3 real + 2 guests) rejected (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 10. Overlap rejected.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
begin
  perform public.create_booking(pg_temp.t(16,0), pg_temp.t(17,0),
                                array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  begin
    perform public.create_booking(pg_temp.t(16,30), pg_temp.t(17,30),
                                  array['11111111-1111-1111-1111-111111111111'::uuid,'33333333-3333-3333-3333-333333333333'::uuid]);
    raise exception 'TESTFAIL: overlapping booking should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 10: overlapping booking rejected (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 11. Open editing: non-member self-joins (RLS insert).
-- ---------------------------------------------------------------------------
begin;
set local role authenticated;
do $$
declare v_b uuid; v_cnt int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  v_b := public.create_booking(pg_temp.t(9,0), pg_temp.t(9,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  -- Carol (NOT a member) self-joins.
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  insert into public.booking_players (booking_id, player_id, added_by)
  values (v_b, '33333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333');
  select count(*) into v_cnt from public.booking_players where booking_id = v_b;
  assert v_cnt = 3, format('expected 3 after self-join, got %s', v_cnt);
  raise notice 'PASS 11: non-member self-join allowed';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 12. Open editing: member adds a guest (RLS insert).
-- ---------------------------------------------------------------------------
begin;
set local role authenticated;
do $$
declare v_b uuid; v_guests int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  v_b := public.create_booking(pg_temp.t(9,0), pg_temp.t(9,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  -- Bob (member) adds a guest.
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  insert into public.booking_players (booking_id, player_id, guest_name, added_by)
  values (v_b, null, 'Zed', '22222222-2222-2222-2222-222222222222');
  select count(*) into v_guests from public.booking_players where booking_id = v_b and player_id is null;
  assert v_guests = 1, format('expected 1 guest, got %s', v_guests);
  raise notice 'PASS 12: member can add a guest';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 13. Cannot remove the creator (deferred constraint).
-- ---------------------------------------------------------------------------
begin;
set local role authenticated;
do $$
declare v_b uuid;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  v_b := public.create_booking(pg_temp.t(9,0), pg_temp.t(9,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid,'33333333-3333-3333-3333-333333333333'::uuid]);
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);  -- Bob (member)
  begin
    delete from public.booking_players where booking_id = v_b and player_id = '11111111-1111-1111-1111-111111111111';
    set constraints all immediate;  -- force the deferred creator-present check
    raise exception 'TESTFAIL: removing creator should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 13: member cannot remove the creator (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 14. Member removes another (non-creator) player; cannot drop below 2.
-- ---------------------------------------------------------------------------
begin;
set local role authenticated;
do $$
declare v_b uuid; v_cnt int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  v_b := public.create_booking(pg_temp.t(9,0), pg_temp.t(9,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid,'33333333-3333-3333-3333-333333333333'::uuid]);
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);  -- Bob (member)
  -- Bob removes Carol (allowed: 3 -> 2)
  delete from public.booking_players where booking_id = v_b and player_id = '33333333-3333-3333-3333-333333333333';
  set constraints all immediate;
  select count(*) into v_cnt from public.booking_players where booking_id = v_b;
  assert v_cnt = 2, format('expected 2 after removing Carol, got %s', v_cnt);
  raise notice 'PASS 14a: member removed another player (3 -> 2)';

  -- Bob now tries to remove himself (2 -> 1) -> should fail at constraint check
  begin
    delete from public.booking_players where booking_id = v_b and player_id = '22222222-2222-2222-2222-222222222222';
    set constraints all immediate;
    raise exception 'TESTFAIL: dropping below 2 should be rejected';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 14b: cannot drop below 2 players (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 15. Non-member cannot remove a player (RLS blocks; 0 rows deleted).
-- ---------------------------------------------------------------------------
begin;
set local role authenticated;
do $$
declare v_b uuid; v_cnt int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  v_b := public.create_booking(pg_temp.t(9,0), pg_temp.t(9,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  -- Carol is NOT a member; tries to remove Bob.
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  delete from public.booking_players where booking_id = v_b and player_id = '22222222-2222-2222-2222-222222222222';
  select count(*) into v_cnt from public.booking_players where booking_id = v_b;
  assert v_cnt = 2, format('expected 2 (delete blocked by RLS), got %s', v_cnt);
  raise notice 'PASS 15: non-member cannot remove a player (RLS)';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 16. Guest gets NO notification (queue has rows only for real players).
--     Run as postgres (RLS bypassed) so we can count all notifications.
-- ---------------------------------------------------------------------------
begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
do $$
declare v_b uuid; v_emails int; v_null_user int;
begin
  v_b := public.create_booking(pg_temp.t(13,30), pg_temp.t(14,0),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid],
                               array['Dave']);
  select count(*) into v_emails from public.notifications
    where booking_id = v_b and channel = 'email' and type = 'booking_created';
  select count(*) into v_null_user from public.notifications where booking_id = v_b and user_id is null;
  assert v_emails = 2, format('expected 2 created-emails (real players only), got %s', v_emails);
  assert v_null_user = 0, 'no notification should have a null user_id';
  raise notice 'PASS 16: guests generate no notifications (% emails for 2 real players)', v_emails;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 17. Direct table CHECK rejects a :15 booking (constraint, not just RPC).
-- ---------------------------------------------------------------------------
begin;
do $$
begin
  begin
    insert into public.bookings (created_by, starts_at, ends_at)
    values ('11111111-1111-1111-1111-111111111111', pg_temp.t(10,15), pg_temp.t(10,45));
    raise exception 'TESTFAIL: table CHECK should reject :15 start';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 17: table CHECK rejects :15 start (%)', sqlerrm;
  end;
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- 18. REGRESSION: membership must be scoped to THE booking, not "any booking".
--     Carol is a member of her own booking C but NOT of Alice+Bob's booking AB.
--     She must not be able to add to / remove from AB.
-- ---------------------------------------------------------------------------
begin;
set local role authenticated;
do $$
declare v_ab uuid; v_cnt int;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  v_ab := public.create_booking(pg_temp.t(9,0), pg_temp.t(9,30),
                               array['11111111-1111-1111-1111-111111111111'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);
  -- Carol creates her own booking C (she is now a member of SOME booking).
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  perform public.create_booking(pg_temp.t(10,0), pg_temp.t(10,30),
                               array['33333333-3333-3333-3333-333333333333'::uuid,'22222222-2222-2222-2222-222222222222'::uuid]);

  -- (a) Carol (not a member of AB) tries to add a guest to AB -> RLS must block.
  begin
    insert into public.booking_players (booking_id, guest_name, added_by)
    values (v_ab, 'Sneaky', '33333333-3333-3333-3333-333333333333');
    raise exception 'TESTFAIL: non-member added a guest to a booking they are not in';
  exception when others then
    if sqlerrm like 'TESTFAIL%' then raise; end if;
    raise notice 'PASS 18a: cross-booking member cannot add guest to AB (%)', sqlerrm;
  end;

  -- (b) Carol tries to remove Bob from AB -> RLS must block (0 rows deleted).
  delete from public.booking_players where booking_id = v_ab and player_id = '22222222-2222-2222-2222-222222222222';
  select count(*) into v_cnt from public.booking_players where booking_id = v_ab;
  assert v_cnt = 2, format('expected AB intact (2), got %s', v_cnt);
  raise notice 'PASS 18b: cross-booking member cannot remove from AB';
end $$;
rollback;

\echo '================ END TESTS ================'
