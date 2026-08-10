-- =====================================================================
-- Supabase compatibility shim for a vanilla PostgreSQL instance.
--
-- Recreates just enough of what a Supabase project provides so the
-- Campus Connect migrations can run and be tested locally:
--   * the anon / authenticated / service_role roles
--   * schema `auth` with users + auth.uid()
--   * schema `storage` with buckets, objects, foldername()
--   * the supabase_realtime publication
--   * Supabase's default privileges on schema public
--
-- Impersonation in tests works the same way PostgREST does it:
--   set local role authenticated;
--   set local request.jwt.claim.sub = '<user uuid>';
-- =====================================================================

-- ---------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------
do $$ begin
  create role anon nologin noinherit;
exception when duplicate_object then null; end $$;

do $$ begin
  create role authenticated nologin noinherit;
exception when duplicate_object then null; end $$;

do $$ begin
  create role service_role nologin noinherit bypassrls;
exception when duplicate_object then null; end $$;

do $$ begin
  create role supabase_auth_admin nologin noinherit;
exception when duplicate_object then null; end $$;

do $$ begin
  create role supabase_storage_admin nologin noinherit;
exception when duplicate_object then null; end $$;


-- ---------------------------------------------------------------------
-- auth schema
-- ---------------------------------------------------------------------
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create extension if not exists pgcrypto;

-- Only the columns the Campus Connect migrations actually touch:
-- id, email and raw_user_meta_data (read by tg_handle_new_auth_user).
create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text unique,
  phone              text unique,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  raw_app_meta_data  jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

grant select on auth.users to authenticated, service_role;

-- Verbatim behaviour of Supabase's auth.uid(): read `sub` out of the
-- request JWT claims. Returns NULL when unauthenticated, which is what
-- makes every `= auth.uid()` policy fail closed.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text;
$$;

create or replace function auth.email()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text;
$$;

grant execute on function auth.uid(), auth.role(), auth.email()
  to anon, authenticated, service_role;


-- ---------------------------------------------------------------------
-- storage schema
-- ---------------------------------------------------------------------
create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id                 text primary key,
  name               text not null unique,
  owner              uuid,
  public             boolean not null default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists storage.objects (
  id             uuid primary key default gen_random_uuid(),
  bucket_id      text references storage.buckets(id),
  name           text,
  owner          uuid,
  metadata       jsonb,
  path_tokens    text[] generated always as (string_to_array(name, '/')) stored,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  last_accessed_at timestamptz not null default now(),
  unique (bucket_id, name)
);

alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;

grant all on storage.objects to authenticated, anon, service_role;
grant select on storage.buckets to authenticated, anon, service_role;

-- Supabase's helper: everything in the path except the final segment.
-- 'chat-media-path/a/b/c.jpg' -> {a,b} for a name of 'a/b/c.jpg'.
create or replace function storage.foldername(name text)
returns text[]
language plpgsql
immutable
as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1 : array_length(_parts, 1) - 1];
end;
$$;

create or replace function storage.filename(name text)
returns text
language plpgsql
immutable
as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[array_length(_parts, 1)];
end;
$$;

create or replace function storage.extension(name text)
returns text
language plpgsql
immutable
as $$
declare
  _parts text[];
  _fn    text;
begin
  select string_to_array(name, '/') into _parts;
  _fn := _parts[array_length(_parts, 1)];
  return reverse(split_part(reverse(_fn), '.', 1));
end;
$$;

grant execute on function storage.foldername(text), storage.filename(text), storage.extension(text)
  to anon, authenticated, service_role;


-- ---------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------
do $$ begin
  create publication supabase_realtime;
exception when duplicate_object then null; end $$;


-- ---------------------------------------------------------------------
-- Default privileges on schema public
-- ---------------------------------------------------------------------
-- Supabase grants these, and the migrations rely on it: 0008 REVOKEs
-- UPDATE on profiles and then re-grants specific columns. Without the
-- baseline grant the revoke is a no-op and RLS would never be exercised.
grant usage on schema public to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
