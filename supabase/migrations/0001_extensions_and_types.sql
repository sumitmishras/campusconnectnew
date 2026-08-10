-- =====================================================================
-- 0001  Extensions, enum types and shared helper functions
-- =====================================================================
-- Everything else in this schema depends on this file. Run it first.
-- Safe to re-run: every statement is idempotent.
-- =====================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid(), digest()
create extension if not exists citext;     -- case-insensitive email / username
create extension if not exists pg_trgm;    -- fuzzy name search on Discover
create extension if not exists btree_gin;  -- mixed scalar + array indexes

-- `private` holds anything the PostgREST API must never expose directly.
create schema if not exists private;
revoke all on schema private from anon, authenticated;


-- ---------------------------------------------------------------------
-- UUID v7 — time-ordered UUIDs
-- ---------------------------------------------------------------------
-- Random v4 UUIDs scatter inserts across the whole B-tree, which wrecks
-- cache locality once a table passes a few hundred million rows (exactly
-- where `messages` is headed). v7 embeds a millisecond timestamp in the
-- high bits, so new rows land at the right edge of the index like a
-- bigserial would, while staying globally unique and unguessable.
--
-- Postgres 18 ships uuidv7() natively; this shim is for 15/17 (Supabase).
create or replace function public.uuid_generate_v7()
returns uuid
language plpgsql
volatile
parallel safe
as $$
begin
  return encode(
    set_bit(
      set_bit(
        overlay(
          uuid_send(gen_random_uuid())
          placing substring(
            int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint)
            from 3
          )
          from 1 for 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex'
  )::uuid;
end;
$$;

comment on function public.uuid_generate_v7() is
  'Time-ordered UUID (RFC 9562 v7). Use as the default PK for high-volume tables.';


-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
-- NOTE for the Flutter side: the Dart models currently serialise enums by
-- `.index` (see user_model.dart toJson). Switch them to the string names
-- below. Index-based serialisation breaks the moment a value is inserted
-- in the middle of an enum, and Postgres enums are text on the wire.

do $$ begin
  create type public.trust_level as enum
    ('trusted', 'new_verified', 'limited', 'restricted', 'suspended');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.verification_level as enum
    ('none', 'phone', 'email', 'student_id', 'ambassador', 'club_rep');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.connection_state as enum
    ('pending', 'accepted', 'declined', 'cancelled', 'withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.conversation_type as enum ('direct', 'group');
exception when duplicate_object then null; end $$;

-- Which campus entity a group conversation belongs to. `adhoc` = a group
-- a student made by hand that is not backed by a club/community/etc.
do $$ begin
  create type public.group_source as enum
    ('community', 'club', 'study_group', 'project', 'event', 'adhoc');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.member_role as enum ('owner', 'admin', 'member');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.message_kind as enum ('text', 'photo', 'document', 'system');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.attachment_kind as enum ('photo', 'document');
exception when duplicate_object then null; end $$;

-- Attachments start `pending` and only become downloadable once the
-- background scanner marks them `clean`.
do $$ begin
  create type public.scan_status as enum ('pending', 'clean', 'infected', 'failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_kind as enum
    ('connection', 'message', 'event', 'poll', 'club', 'project', 'system');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.report_state as enum ('open', 'reviewing', 'actioned', 'dismissed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.rsvp_state as enum ('going', 'interested', 'not_going');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_level as enum ('all', 'mentions', 'none');
exception when duplicate_object then null; end $$;


-- ---------------------------------------------------------------------
-- Shared triggers
-- ---------------------------------------------------------------------
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- Academic year helper
-- ---------------------------------------------------------------------
-- Mirrors CuIdentity.yearOfStudy in lib/core/services/cu_identity.dart:
-- the session rolls over in July and the result is clamped to 1..4.
--
-- Deliberately NOT stored on the profile: a student's year changes every
-- July without anyone touching the row. Store `admission_year` (a fact)
-- and derive the year of study (a view of that fact) at read time.
--
-- This function is STABLE, not IMMUTABLE, so it cannot back an index.
-- To filter Discover by "3rd Year", translate the label to an
-- admission_year in the backend and filter on the indexed column —
-- see public.admission_year_for_study_year() below.
create or replace function public.study_year(p_admission_year int, p_at timestamptz default now())
returns int
language sql
stable
parallel safe
as $$
  select greatest(1, least(4,
    extract(year from p_at)::int - p_admission_year
      + case when extract(month from p_at)::int >= 7 then 1 else 0 end
  ));
$$;

create or replace function public.admission_year_for_study_year(p_study_year int, p_at timestamptz default now())
returns int
language sql
stable
parallel safe
as $$
  select extract(year from p_at)::int - p_study_year
       + case when extract(month from p_at)::int >= 7 then 1 else 0 end;
$$;

comment on function public.admission_year_for_study_year(int, timestamptz) is
  'Inverse of study_year(). Use in WHERE clauses so the query hits the index on profiles.admission_year.';
