-- =====================================================================
-- 0003  Connections, blocks, profile views
-- =====================================================================


-- ---------------------------------------------------------------------
-- Connections
-- ---------------------------------------------------------------------
-- One row per relationship, not two. A "connection" is symmetric once
-- accepted, so storing both directions would double the table and open
-- the door to the two halves disagreeing. The direction that matters
-- (who asked whom) is kept in requester_id / addressee_id.
create table if not exists public.connections (
  id           uuid primary key default public.uuid_generate_v7(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  state        public.connection_state not null default 'pending',
  -- "Study partner", "Project collab" … shown on the request card.
  purpose      text check (length(purpose) <= 200),
  message      text check (length(message) <= 300),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,

  -- Canonical unordered pair, so (A,B) and (B,A) collide.
  pair_key text generated always as (
    least(requester_id::text, addressee_id::text) || ':' ||
    greatest(requester_id::text, addressee_id::text)
  ) stored,

  constraint connections_no_self check (requester_id <> addressee_id)
);

-- Only ONE live relationship per pair. Declined/cancelled rows stay for
-- history and rate-limiting, and do not block a fresh request later.
create unique index if not exists connections_active_pair_uniq
  on public.connections (pair_key)
  where state in ('pending', 'accepted');

-- "My connections" and "requests waiting on me" — the two hot reads.
create index if not exists connections_addressee_pending_idx
  on public.connections (addressee_id, created_at desc)
  where state = 'pending';

create index if not exists connections_requester_pending_idx
  on public.connections (requester_id, created_at desc)
  where state = 'pending';

create index if not exists connections_accepted_a_idx
  on public.connections (requester_id, responded_at desc) where state = 'accepted';

create index if not exists connections_accepted_b_idx
  on public.connections (addressee_id, responded_at desc) where state = 'accepted';

-- Spam brake: how many requests this student fired off recently.
create index if not exists connections_requester_recent_idx
  on public.connections (requester_id, created_at desc);


-- Cheap membership test used all over the RLS policies and the chat
-- gate. SECURITY DEFINER so it can read `connections` without tripping
-- that table's own RLS and recursing.
create or replace function public.are_connected(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.connections
    where state = 'accepted'
      and pair_key = least(a::text, b::text) || ':' || greatest(a::text, b::text)
  );
$$;


-- ---------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------
-- Directional on purpose: A blocking B is not B blocking A. Enforcement
-- is symmetric though — neither can see or message the other.
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  reason     text,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_no_self check (blocker_id <> blocked_id)
);

-- Reverse lookup: "who has blocked me", needed to filter Discover.
create index if not exists blocks_blocked_idx on public.blocks (blocked_id);

create or replace function public.is_blocked_either_way(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;


-- When a block goes up, tear down the connection. Keeping an "accepted"
-- connection alongside a block is the kind of inconsistency that later
-- shows up as a stranger appearing in someone's chat list.
create or replace function public.tg_block_severs_connection()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.connections
     set state = 'cancelled', responded_at = now()
   where state in ('pending', 'accepted')
     and pair_key = least(new.blocker_id::text, new.blocked_id::text) || ':' ||
                    greatest(new.blocker_id::text, new.blocked_id::text);
  return new;
end;
$$;

create or replace trigger block_severs_connection after insert on public.blocks
  for each row execute function public.tg_block_severs_connection();


-- ---------------------------------------------------------------------
-- Profile views
-- ---------------------------------------------------------------------
-- "Who viewed my profile" plus a signal for the Discover ranker.
-- Deliberately lossy: one row per viewer/viewed pair per day, upserted.
-- Logging every single view would out-write the messages table for data
-- nobody reads twice.
create table if not exists public.profile_views (
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  viewed_id  uuid not null references public.profiles(id) on delete cascade,
  view_date  date not null default current_date,
  view_count integer not null default 1,
  last_seen  timestamptz not null default now(),
  primary key (viewed_id, view_date, viewer_id),
  constraint profile_views_no_self check (viewer_id <> viewed_id)
);

comment on table public.profile_views is
  'Retention: drop rows older than 90 days via the nightly cleanup job.';
