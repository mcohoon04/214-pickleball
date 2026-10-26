-- Keep pg_cron / pg_net housekeeping tables from growing without bound.
--
-- send-pending-notifications runs every minute, and pg_cron logs every run to
-- cron.job_run_details. Nothing ever pruned it: by 2026-10-21 it held 288k rows
-- (460 MB), and net._http_response had bloated to 194 MB. That put the database
-- (669 MB) over the Free plan's 500 MB limit and starved the Nano instance of
-- memory. Cron runs began failing with "job startup timeout" (41% of runs the
-- week of 2026-10-12), which made notifications late.
--
-- Fix: once a day, delete cron run logs older than 30 days, then VACUUM both
-- tables so the freed space is reused. (The one-time purge plus VACUUM FULL was
-- run by hand on 2026-10-22; this migration only adds the recurring jobs.)
-- VACUUM can't run inside a transaction, so each step is its own job.

select cron.schedule(
  'prune-cron-run-details',
  '15 7 * * *', -- 07:15 UTC daily (~3 AM Toronto)
  $$delete from cron.job_run_details where start_time < now() - interval '30 days'$$
);

select cron.schedule(
  'vacuum-cron-run-details',
  '25 7 * * *',
  $$vacuum cron.job_run_details$$
);

select cron.schedule(
  'vacuum-http-response',
  '35 7 * * *',
  $$vacuum net._http_response$$
);
