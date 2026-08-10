-- =====================================================================
-- 0006  Notifications, moderation, rate limiting, audit
-- =====================================================================


-- ---------------------------------------------------------------------
-- Notifications  (hash partitioned by user_id)
-- ---------------------------------------------------------------------
-- Highest-volume table after `messages`: a single popular event can
-- generate one row per attendee. Every read is "my notifications, newest
-- first", so hashing on user_id prunes each read to one partition and
-- keeps one noisy user's rows out of everyone else's index pages.
create table if not exists public.notifications (
  user_id uuid not null,
  id      uuid not null default public.uuid_generate_v7(),

  kind  public.notification_kind not null,
  title text not null,
  body  text not null default '',

  -- Who/what triggered it, for the tap-through and the avatar.
  actor_id    uuid references public.profiles(id) on delete set null,
  target_type text,
  target_id   uuid,
  -- Deep link the app routes on, e.g. '/chat/<conversation_id>'.
  deep_link   text,

  read_at    timestamptz,
  -- Push delivery state, so a retry job can find what never went out.
  pushed_at  timestamptz,
  created_at timestamptz not null default now(),

  primary key (user_id, id)
) partition by hash (user_id);

do $$
declare i int;
begin
  for i in 0..7 loop
    execute format(
      'create table if not exists public.notifications_p%s partition of public.notifications
         for values with (modulus 8, remainder %s)', i, i);
  end loop;
end $$;

-- The notification list. id is v7, so ordering by it is ordering by time
-- and this index alone serves the screen.
create index if not exists notifications_feed_idx
  on public.notifications (user_id, id desc);

-- The unread badge. Partial index — usually a handful of rows per user.
create index if not exists notifications_unread_idx
  on public.notifications (user_id, id desc)
  where read_at is null;

-- Push retry queue.
create index if not exists notifications_push_pending_idx
  on public.notifications (created_at)
  where pushed_at is null;

comment on table public.notifications is
  'Retention: 60 days. The nightly job deletes older rows partition by partition.';


-- Per-user notification preferences (settings_screen.dart).
create table if not exists public.notification_settings (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  connections boolean not null default true,
  messages    boolean not null default true,
  events      boolean not null default true,
  clubs       boolean not null default true,
  polls       boolean not null default false,
  system      boolean not null default true,
  -- Local time window during which pushes are suppressed.
  quiet_hours_start time,
  quiet_hours_end   time,
  timezone    text not null default 'Asia/Kolkata',
  updated_at  timestamptz not null default now()
);

create or replace trigger set_updated_at before update on public.notification_settings
  for each row execute function public.tg_set_updated_at();


-- ---------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------
create table if not exists public.reports (
  id          uuid primary key default public.uuid_generate_v7(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,

  -- What is being reported. Polymorphic: a profile, a message, an event…
  target_type text not null
                check (target_type in ('profile', 'message', 'conversation', 'event', 'project', 'poll', 'club')),
  target_id   uuid not null,
  -- For message reports, so a moderator can open the thread in context.
  conversation_id uuid references public.conversations(id) on delete set null,
  -- Snapshot of the reported content. The original may be deleted before
  -- review; without this the report becomes unreviewable.
  content_snapshot jsonb,

  reason  text not null
            check (reason in ('spam', 'harassment', 'hate_speech', 'nudity',
                              'impersonation', 'scam', 'self_harm', 'other')),
  details text check (length(details) <= 1000),

  state       public.report_state not null default 'open',
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  resolution  text,
  created_at  timestamptz not null default now()
);

-- Moderator queue, oldest first.
create index if not exists reports_queue_idx
  on public.reports (created_at)
  where state in ('open', 'reviewing');

-- "Everything reported about this user/message."
create index if not exists reports_target_idx
  on public.reports (target_type, target_id, created_at desc);

-- Stops one person mass-reporting the same target.
create unique index if not exists reports_no_duplicate_open_uniq
  on public.reports (reporter_id, target_type, target_id)
  where state in ('open', 'reviewing');


-- Keep profiles.report_count current so the trust rules can read it
-- without an aggregate.
create or replace function public.tg_report_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.target_type = 'profile' then
    update public.profiles
       set report_count = report_count + 1
     where id = new.target_id;
  end if;
  return null;
end;
$$;

create or replace trigger report_count after insert on public.reports
  for each row execute function public.tg_report_count();


-- ---------------------------------------------------------------------
-- Moderation actions
-- ---------------------------------------------------------------------
-- Append-only. Never update or delete a row here — this is the record
-- that answers "why was I banned" and "who banned them".
create table if not exists public.moderation_actions (
  id          uuid primary key default public.uuid_generate_v7(),
  subject_id  uuid not null references public.profiles(id) on delete cascade,
  moderator_id uuid references public.profiles(id) on delete set null,
  report_id   uuid references public.reports(id) on delete set null,

  action text not null
           check (action in ('warn', 'strike', 'mute', 'restrict', 'suspend',
                             'unsuspend', 'delete_content', 'verify', 'unverify')),
  reason text not null,
  -- NULL for permanent actions.
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists moderation_subject_idx
  on public.moderation_actions (subject_id, created_at desc);

-- What the enforcement check reads: "is this user currently muted or
-- suspended". No WHERE clause here even though only live actions are
-- ever queried: an index predicate must be IMMUTABLE, and now() is only
-- STABLE — a predicate that changes meaning over time would leave rows
-- silently unindexed. `expires_at` is the third key column instead, so
-- `WHERE subject_id = ? AND action = ? AND (expires_at IS NULL OR
-- expires_at > now())` still resolves inside the index.
create index if not exists moderation_active_idx
  on public.moderation_actions (subject_id, action, expires_at);


-- ---------------------------------------------------------------------
-- Rate limiting
-- ---------------------------------------------------------------------
-- A fixed-window counter per (user, action, window). Cheap to check
-- because the whole row is found by primary key, and old windows are
-- dropped by the nightly job rather than being counted over.
--
-- This is the DB-side backstop. The real per-request limiter belongs in
-- the Node gateway (Redis, sliding window) — this catches what slips
-- past it and anything hitting PostgREST directly.
create table if not exists public.rate_limits (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  action       text not null,      -- 'send_message', 'connect_request', 'report'
  window_start timestamptz not null,
  count        integer not null default 1,
  primary key (user_id, action, window_start)
) with (fillfactor = 70);

create index if not exists rate_limits_sweep_idx on public.rate_limits (window_start);


create or replace function public.check_rate_limit(
  p_user   uuid,
  p_action text,
  p_limit  integer,
  p_window interval default interval '1 minute'
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start timestamptz := date_bin(p_window, now(), timestamptz 'epoch');
  v_count integer;
begin
  insert into public.rate_limits (user_id, action, window_start, count)
  values (p_user, p_action, v_start, 1)
  on conflict (user_id, action, window_start)
    do update set count = rate_limits.count + 1
  returning rate_limits.count into v_count;

  return v_count <= p_limit;
end;
$$;

comment on function public.check_rate_limit(uuid, text, integer, interval) is
  'Returns false once p_user has exceeded p_limit actions in the current window. '
  'SERVICE ROLE / SECURITY DEFINER CALLERS ONLY — it takes an arbitrary user id, '
  'so exposing it to clients would let anyone burn through someone else''s quota. '
  'Client-reachable code (including RLS policies) must use check_my_rate_limit().';


-- The client-safe form. RLS policy expressions are evaluated with the
-- caller's privileges, so a policy cannot call check_rate_limit() unless
-- `authenticated` may execute it — and the moment they can, they can
-- exhaust another student's quota by passing that student's id. This
-- wrapper closes p_user to auth.uid() and is the only version granted.
create or replace function public.check_my_rate_limit(
  p_action text,
  p_limit  integer,
  p_window interval default interval '1 minute'
) returns boolean
language sql
security definer
set search_path = public
as $$
  select public.check_rate_limit(auth.uid(), p_action, p_limit, p_window);
$$;

revoke all on function public.check_rate_limit(uuid, text, integer, interval) from public, anon, authenticated;
revoke all on function public.check_my_rate_limit(text, integer, interval) from public, anon;
grant execute on function public.check_my_rate_limit(text, integer, interval) to authenticated;


-- ---------------------------------------------------------------------
-- Trust level automation
-- ---------------------------------------------------------------------
-- Trust is derived, not hand-set: verification climbs it, strikes drop
-- it. Keeping the rule in one trigger means the app can never write a
-- trust level that contradicts the evidence.
create or replace function public.tg_recompute_trust_level()
returns trigger
language plpgsql
as $$
begin
  new.trust_level := case
    when new.strike_count >= 3 then 'suspended'
    when new.strike_count = 2  then 'restricted'
    when new.report_count >= 5 then 'limited'
    when new.verification_level in ('student_id', 'ambassador', 'club_rep')
      and new.created_at < now() - interval '14 days' then 'trusted'
    else 'new_verified'
  end::public.trust_level;
  return new;
end;
$$;

create or replace trigger recompute_trust_level
  before update of strike_count, report_count, verification_level on public.profiles
  for each row execute function public.tg_recompute_trust_level();


-- ---------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------
create table if not exists public.audit_log (
  id         bigint generated always as identity primary key,
  actor_id   uuid references public.profiles(id) on delete set null,
  action     text not null,
  entity     text not null,
  entity_id  uuid,
  before     jsonb,
  after      jsonb,
  ip         inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists audit_log_entity_idx
  on public.audit_log (entity, entity_id, created_at desc);

create index if not exists audit_log_actor_idx
  on public.audit_log (actor_id, created_at desc);
