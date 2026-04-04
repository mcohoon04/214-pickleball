-- Seed invite code for local development
insert into public.invite_codes (code) values ('PICKLE214');

-- Vault secrets for local cron job (matches supabase start output)
-- The project_url uses Docker internal host since Postgres runs in a container
select vault.create_secret('http://host.docker.internal:54321', 'project_url');
-- Note: service_role_key must be pasted from `supabase status` output after first start
-- select vault.create_secret('YOUR_LOCAL_SERVICE_ROLE_KEY', 'service_role_key');
