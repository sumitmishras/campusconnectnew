-- 0014_uid_lookup.sql
--
-- One entry screen for both sign-in and sign-up.
--
-- The app now asks for a university id on its own -- "21bcs5084", no domain --
-- and decides from the answer whether the next screen greets a returning
-- student or starts the registration wizard. That decision has to be made
-- *before* anyone is signed in, and 0008 puts `profiles` behind RLS that only
-- `authenticated` can read, so an ordinary select cannot answer it.
--
-- This function is the narrowest hole that answers it: one uid in, one boolean
-- out, executable by `anon`. `security definer` lets it see past RLS;
-- `search_path` is pinned so the definer's rights cannot be redirected at a
-- table of the caller's choosing.
--
-- "Exists" deliberately means *finished*, not merely present.
-- `tg_handle_new_auth_user` (0002) inserts a profile shell in the same
-- transaction as the auth row, so a student who once asked for a code and then
-- abandoned the wizard already has a row. Keying off `onboarding_completed_at`
-- -- the same column `ProfileRepository.fetchCurrent()` uses to decide the
-- wizard is done -- sends that student back into sign-up instead of telling
-- them they already have an account and then dropping them into the wizard
-- anyway.
--
-- Soft-deleted profiles are excluded for the same reason: the purge job
-- (0010) only hard-deletes after the grace period, and until then the id
-- should behave as if it were free.
--
-- On enumeration: this does let an unauthenticated caller test whether a given
-- id has an account. That is the unavoidable price of telling a student which
-- flow they are in before they type anything else. It leaks existence and
-- nothing else -- no name, no email, no profile data -- and CU ids are
-- sequential and printed on the ID card, so they were never secret. If this
-- ever needs tightening, rate-limit it at the gateway rather than removing it,
-- because the UI depends on the answer.

create or replace function public.uid_exists(p_uid citext)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles
    where university_uid = trim(p_uid)
      and onboarding_completed_at is not null
      and deleted_at is null
  );
$$;

comment on function public.uid_exists(citext) is
  'True when a completed, non-deleted profile owns this university id. '
  'Callable by anon so the single entry screen can choose between sign-in '
  'and sign-up before a session exists. Returns existence only.';

revoke all on function public.uid_exists(citext) from public;
grant execute on function public.uid_exists(citext) to anon, authenticated;
