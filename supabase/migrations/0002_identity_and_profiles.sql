-- =====================================================================
-- 0002  Universities, programs, profiles, presence, badges, devices
-- =====================================================================
-- Authentication itself lives in Supabase's `auth.users`. Everything the
-- app knows about a student lives in `public.profiles`, keyed 1:1 to it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Tenancy
-- ---------------------------------------------------------------------
-- Campus Connect launches on Chandigarh University only, but the whole
-- data model is scoped by university from day one. Retro-fitting a tenant
-- key onto a live table with a hundred million rows is a weekend outage;
-- carrying an extra uuid now costs nothing. Every discovery query filters
-- on it, which also keeps one campus's traffic off another's index pages.
create table if not exists public.universities (
  id            uuid primary key default public.uuid_generate_v7(),
  slug          citext not null unique,          -- 'cu'
  name          text   not null,                 -- 'Chandigarh University'
  short_name    text   not null,                 -- 'CU'
  email_domain  citext not null unique,          -- 'cuchd.in'
  -- Regex a login id must match, e.g. '^(\d{2})([a-z]{3})(\d{3,5})$'
  uid_pattern   text   not null,
  logo_url      text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create or replace trigger set_updated_at before update on public.universities
  for each row execute function public.tg_set_updated_at();


-- Programme codes: the `_programs` map in cu_identity.dart, but in the DB
-- so a new course can be added without shipping an app update.
create table if not exists public.programs (
  id             uuid primary key default public.uuid_generate_v7(),
  university_id  uuid not null references public.universities(id) on delete cascade,
  code           citext not null,                -- 'bcs'
  department     text   not null,                -- 'Computer Science'
  course         text   not null,                -- 'B.E. CSE'
  duration_years smallint not null default 4,
  is_active      boolean not null default true,
  unique (university_id, code)
);

create index if not exists programs_university_idx
  on public.programs (university_id) where is_active;


-- Canonical tag vocabulary for interests / languages / "looking for".
-- Profiles keep denormalised text[] copies (see below) — this table only
-- powers autocomplete and stops the tag list turning into 4000 spellings
-- of "photography".
create table if not exists public.tags (
  slug        citext primary key,        -- 'coding'
  label       text not null,             -- 'Coding'
  category    text not null check (category in ('interest', 'language', 'looking_for', 'skill')),
  usage_count integer not null default 0,
  is_active   boolean not null default true
);

create index if not exists tags_category_idx
  on public.tags (category, usage_count desc) where is_active;


-- ---------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  university_id  uuid not null references public.universities(id),

  -- Identity ---------------------------------------------------------
  full_name      text   not null check (length(trim(full_name)) between 2 and 80),
  username       citext not null check (username ~ '^[a-z0-9_.]{3,30}$'),
  email          citext not null,
  -- University login id, lower case: '21bcs5084'
  university_uid citext not null,
  phone_e164     text check (phone_e164 ~ '^\+[1-9]\d{7,14}$'),
  gender         text not null default 'Prefer not to say',
  date_of_birth  date,

  -- Academics --------------------------------------------------------
  program_id     uuid references public.programs(id),
  -- Denormalised from `programs` so the Discover list needs no join.
  -- Kept in sync by tg_profile_sync_program below.
  department     text not null default '',
  course         text not null default '',
  admission_year smallint not null check (admission_year between 2000 and 2100),
  roll_number    text,

  -- Profile content ---------------------------------------------------
  bio            text not null default '' check (length(bio) <= 500),
  campus_status  text check (length(campus_status) <= 100),
  avatar_path    text,          -- object key in the `avatars` bucket
  avatar_url     text,          -- cached public/CDN URL

  -- Arrays, not join tables. A student has <20 of each, they are always
  -- read together with the profile, and `interests && $1` on a GIN index
  -- beats a join for the Discover filter. `tags` above keeps them clean.
  interests      text[] not null default '{}' check (cardinality(interests) <= 20),
  languages      text[] not null default '{}' check (cardinality(languages) <= 10),
  looking_for    text[] not null default '{}' check (cardinality(looking_for) <= 10),

  -- Trust & safety -----------------------------------------------------
  trust_level        public.trust_level        not null default 'new_verified',
  verification_level public.verification_level not null default 'none',
  -- Rolling counters the moderation rules read; maintained by triggers.
  report_count       integer not null default 0,
  strike_count       integer not null default 0,

  -- Privacy toggles (mirrors the switches in privacy_settings_screen).
  hide_department     boolean not null default false,
  hide_year           boolean not null default false,
  hide_looking_for    boolean not null default false,
  hide_active_status  boolean not null default false,
  discoverable        boolean not null default true,
  allow_dm_from_anyone boolean not null default false,

  -- Lifecycle ----------------------------------------------------------
  onboarding_completed_at timestamptz,
  deactivated_at timestamptz,
  deleted_at     timestamptz,     -- soft delete; purge job hard-deletes later
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- Full-text search vector for the Discover search box.
  search_vector tsvector generated always as (
    setweight(to_tsvector('simple', coalesce(full_name, '')),  'A') ||
    setweight(to_tsvector('simple', coalesce(username, '')),   'A') ||
    setweight(to_tsvector('simple', coalesce(department, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(bio, '')),        'C')
  ) stored,

  unique (university_id, username),
  unique (university_id, university_uid),
  unique (university_id, email)
);

create or replace trigger set_updated_at before update on public.profiles
  for each row execute function public.tg_set_updated_at();

-- Discover's primary filter: same campus, optionally same department /
-- batch. Partial on the soft-delete + privacy flags so the index only
-- holds rows that can actually be returned.
create index if not exists profiles_discover_idx
  on public.profiles (university_id, department, admission_year)
  where deleted_at is null and deactivated_at is null and discoverable;

create index if not exists profiles_interests_gin
  on public.profiles using gin (interests)
  where deleted_at is null and discoverable;

create index if not exists profiles_looking_for_gin
  on public.profiles using gin (looking_for)
  where deleted_at is null and discoverable;

create index if not exists profiles_search_idx
  on public.profiles using gin (search_vector)
  where deleted_at is null and discoverable;

-- Trigram index for "did you mean" partial name matches, which tsvector
-- cannot do (it only matches whole lexemes).
create index if not exists profiles_name_trgm_idx
  on public.profiles using gin (full_name gin_trgm_ops)
  where deleted_at is null and discoverable;

create index if not exists profiles_created_idx
  on public.profiles (university_id, created_at desc);


-- Keep the denormalised department/course in step with program_id.
create or replace function public.tg_profile_sync_program()
returns trigger
language plpgsql
as $$
begin
  if new.program_id is not null and
     (tg_op = 'INSERT' or new.program_id is distinct from old.program_id) then
    select p.department, p.course into new.department, new.course
    from public.programs p where p.id = new.program_id;
  end if;
  return new;
end;
$$;

create or replace trigger sync_program before insert or update of program_id on public.profiles
  for each row execute function public.tg_profile_sync_program();


-- ---------------------------------------------------------------------
-- Presence — deliberately a separate table
-- ---------------------------------------------------------------------
-- `is_online` / `last_active` change every few seconds per active user.
-- Living on `profiles`, each heartbeat would rewrite a wide row carrying
-- five GIN indexes and a generated tsvector — the single fastest way to
-- kill this database at 100k users. Here the row is narrow, has no
-- secondary indexes, and gets fillfactor headroom so updates stay HOT
-- (no index maintenance, no table bloat).
--
-- At real scale the write path should be Redis with a periodic flush into
-- this table; the schema is the same either way.
create table if not exists public.user_presence (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  is_online   boolean not null default false,
  last_active timestamptz not null default now(),
  -- Which socket/server currently holds the connection (chat server uses
  -- this to route; null when offline).
  node_id     text
) with (fillfactor = 70);

comment on table public.user_presence is
  'Hot-write table. Never add secondary indexes here — updates must stay HOT.';


-- ---------------------------------------------------------------------
-- Badges & achievements
-- ---------------------------------------------------------------------
-- Modelled as rows, not a text[] on the profile: badges are awarded by
-- the system, need an award timestamp and a granting reason for appeals,
-- and admins need to list "everyone with badge X".
create table if not exists public.badges (
  slug        citext primary key,
  label       text not null,
  description text not null default '',
  icon        text,
  color       text
);

create table if not exists public.profile_badges (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  badge_slug citext not null references public.badges(slug) on delete cascade,
  awarded_at timestamptz not null default now(),
  awarded_by uuid references public.profiles(id),
  reason     text,
  primary key (profile_id, badge_slug)
);

create index if not exists profile_badges_badge_idx
  on public.profile_badges (badge_slug, awarded_at desc);


-- ---------------------------------------------------------------------
-- Verification submissions
-- ---------------------------------------------------------------------
create table if not exists public.verification_requests (
  id            uuid primary key default public.uuid_generate_v7(),
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  target_level  public.verification_level not null,
  -- Object key in the private `verification-docs` bucket.
  document_path text,
  status        text not null default 'pending'
                  check (status in ('pending', 'approved', 'rejected')),
  reviewed_by   uuid references public.profiles(id),
  reviewed_at   timestamptz,
  review_note   text,
  created_at    timestamptz not null default now()
);

create index if not exists verification_pending_idx
  on public.verification_requests (created_at)
  where status = 'pending';


-- ---------------------------------------------------------------------
-- Devices / push tokens
-- ---------------------------------------------------------------------
create table if not exists public.user_devices (
  id             uuid primary key default public.uuid_generate_v7(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  -- FCM / APNs registration token.
  push_token     text not null,
  platform       text not null check (platform in ('android', 'ios', 'web')),
  app_version    text,
  device_model   text,
  locale         text,
  last_seen_at   timestamptz not null default now(),
  push_enabled   boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (push_token)
);

create index if not exists user_devices_user_idx
  on public.user_devices (user_id) where push_enabled;


-- ---------------------------------------------------------------------
-- Auto-create a profile shell when a user signs up
-- ---------------------------------------------------------------------
-- The registration wizard then fills in the rest via an UPDATE. Doing the
-- insert here means there is never a window where an auth.users row has
-- no profile, which would break every foreign key downstream.
create or replace function public.tg_handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email      citext := new.email;
  v_domain     citext;
  v_uni        public.universities%rowtype;
  v_uid        citext;
  v_code       citext;
  v_year       smallint;
  v_roll       text;
  v_program_id uuid;
  v_match      text[];
begin
  if v_email is null then
    return new;
  end if;

  v_domain := split_part(v_email, '@', 2);
  v_uid    := lower(split_part(v_email, '@', 1));

  select * into v_uni from public.universities where email_domain = v_domain and is_active;
  if not found then
    raise exception 'Sign-ups are limited to registered campus email domains (got %)', v_domain
      using errcode = 'check_violation';
  end if;

  v_match := regexp_match(v_uid, v_uni.uid_pattern);
  if v_match is null then
    raise exception '% does not look like a valid % university id', v_uid, v_uni.short_name
      using errcode = 'check_violation';
  end if;

  v_year := 2000 + v_match[1]::int;
  v_code := v_match[2];
  v_roll := v_match[3];

  select id into v_program_id
  from public.programs
  where university_id = v_uni.id and code = v_code and is_active;

  insert into public.profiles (
    id, university_id, full_name, username, email,
    university_uid, program_id, admission_year, roll_number,
    verification_level
  ) values (
    new.id, v_uni.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), v_uid),
    v_uid,                      -- CuIdentity.suggestedUsername
    v_email, v_uid, v_program_id, v_year, v_roll,
    'email'                     -- they proved control of the campus inbox
  )
  on conflict (id) do nothing;

  insert into public.user_presence (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.tg_handle_new_auth_user();
