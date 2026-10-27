-- Seed court code for local development (table was renamed invite_codes -> court_codes)
insert into public.court_codes (code, court_name) values ('PICKLE214', '214 Pickle');

-- Vault secrets for local cron job (matches supabase start output)
-- The project_url uses Docker internal host since Postgres runs in a container
select vault.create_secret('http://host.docker.internal:54321', 'project_url');
-- Note: service_role_key must be pasted from `supabase status` output after first start
-- select vault.create_secret('YOUR_LOCAL_SERVICE_ROLE_KEY', 'service_role_key');
-- cron_secret must match the CRON_SECRET function secret (supabase/functions/.env for local serve)
-- select vault.create_secret('<random value>', 'cron_secret');
