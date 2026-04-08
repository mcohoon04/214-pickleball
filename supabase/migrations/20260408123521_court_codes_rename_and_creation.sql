-- Rename invite_codes → court_codes, add court_name and created_by

alter table public.invite_codes rename to court_codes;

alter table public.court_codes
  add column court_name text not null default '214 Pickle',
  add column created_by uuid references auth.users (id) on delete set null;

-- Update existing code with defaults
update public.court_codes set court_name = '214 Pickle' where court_name = '214 Pickle';

-- Replace validate_invite_code with validate_court_code
drop function if exists public.validate_invite_code(text);

create or replace function public.validate_court_code(p_code text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.court_codes
    where code = upper(trim(p_code)) and is_active = true
  );
$$;

revoke all on function public.validate_court_code(text) from public;
grant execute on function public.validate_court_code(text) to anon, authenticated;

-- RPC to create a new court (requires authenticated user)
create or replace function public.create_court(p_court_name text, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_clean_code text;
begin
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  v_clean_code := upper(trim(p_code));

  if char_length(v_clean_code) < 4 or char_length(v_clean_code) > 20 then
    raise exception 'Court code must be between 4 and 20 characters';
  end if;

  if char_length(trim(p_court_name)) < 2 then
    raise exception 'Court name is too short';
  end if;

  -- Check if code already exists
  if exists (select 1 from public.court_codes where code = v_clean_code) then
    raise exception 'This court code is already taken';
  end if;

  insert into public.court_codes (code, court_name, created_by)
  values (v_clean_code, trim(p_court_name), v_caller);

  return v_clean_code;
end;
$$;

revoke all on function public.create_court(text, text) from public;
grant execute on function public.create_court(text, text) to authenticated;
