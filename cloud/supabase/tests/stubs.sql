-- Minimal stand-ins for what a Supabase project provides, so the migration
-- can be checked on plain Postgres without Docker or the Supabase CLI.
-- Never applied to a real project.
do $$ begin
  if not exists (select from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create schema realtime;
create table realtime.messages (topic text, extension text, payload jsonb);
alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$
  select current_setting('realtime.topic', true)
$$;
grant usage on schema auth, realtime, public to anon, authenticated;
grant execute on all functions in schema auth, realtime to authenticated;
grant select, insert on realtime.messages to authenticated;
create publication supabase_realtime;
