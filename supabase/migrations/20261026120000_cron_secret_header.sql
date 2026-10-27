-- Restrict send-notifications to the pg_cron job.
--
-- The function runs with verify_jwt, which also admits any signed-in app user,
-- so any member could trigger a queue drain. The cron job now also sends an
-- x-cron-secret header, and the function rejects requests without it.
--
-- Requires, before deploying the function (value never committed):
--   select vault.create_secret('<random value>', 'cron_secret');
--   supabase secrets set CRON_SECRET=<same value>
--
-- cron.schedule with an existing job name updates that job in place.

-- Where the cron job is wired up (project_url in Vault), refuse to apply without
-- cron_secret: pg_net drops null headers, so every call would be rejected once
-- the function is deployed. A fresh local reset has no Vault secrets yet
-- (seed.sql runs after migrations), so the check is skipped there.
do $$
begin
  if exists (select 1 from vault.decrypted_secrets where name = 'project_url')
     and not exists (
       select 1 from vault.decrypted_secrets
       where name = 'cron_secret' and coalesce(decrypted_secret, '') <> ''
     ) then
    raise exception 'Vault secret cron_secret is missing or empty: create it (and the CRON_SECRET function secret) first';
  end if;
end;
$$;

select
  cron.schedule(
    'send-pending-notifications',
    '* * * * *',
    $$
    select
      net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
               || '/functions/v1/send-notifications',
        headers := jsonb_build_object(
          'Content-type', 'application/json',
          'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
          'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
        ),
        body := '{}'::jsonb
      ) as request_id;
    $$
  );
