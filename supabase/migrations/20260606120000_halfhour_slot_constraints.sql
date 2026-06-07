-- Half-hour slot granularity.
--
-- Bookings may now start and end on :00 OR :30 (previously on-the-hour only).
-- The on-the-hour rule was enforced in two table CHECK constraints:
--   * an UNNAMED check from the initial schema:
--       date_part('minute', starts_at) = 0 and date_part('second', starts_at) = 0
--   * bookings_ends_at_on_hour (from the multi-hour migration) on ends_at
-- The create_booking RPC's matching guards are relaxed in the next migration.

begin;

-- 1. Drop the unnamed initial-schema on-the-hour check on starts_at.
--    Matched by its definition (references minute + second of starts_at).
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.bookings'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%minute%starts_at%'
      and pg_get_constraintdef(oid) ilike '%second%starts_at%'
      and pg_get_constraintdef(oid) not ilike '%30%'   -- never match the new half-hour check
  loop
    execute format('alter table public.bookings drop constraint %I', r.conname);
  end loop;
end;
$$;

-- 2. Drop the named ends_at on-the-hour check.
alter table public.bookings drop constraint if exists bookings_ends_at_on_hour;

-- 3. Re-add half-hour-aware checks: minute in (0, 30), second = 0.
alter table public.bookings drop constraint if exists bookings_starts_on_half_hour;
alter table public.bookings add constraint bookings_starts_on_half_hour
  check (date_part('minute', starts_at) in (0, 30) and date_part('second', starts_at) = 0);

alter table public.bookings drop constraint if exists bookings_ends_on_half_hour;
alter table public.bookings add constraint bookings_ends_on_half_hour
  check (date_part('minute', ends_at) in (0, 30) and date_part('second', ends_at) = 0);

commit;
