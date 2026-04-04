-- pg_cron job: invoke send-notifications Edge Function every 60 seconds.
-- Vault stores credentials so they're not hardcoded in the cron job SQL.
-- For local dev, Vault secrets are populated by seed.sql.
-- For production, run manually after deploy:
--   select vault.create_secret('<project-url>', 'project_url');
--   select vault.create_secret('<service-role-key>', 'service_role_key');

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
          'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
        ),
        body := '{}'::jsonb
      ) as request_id;
    $$
  );
