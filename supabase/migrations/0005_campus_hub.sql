-- =====================================================================
-- 0005  Campus Hub: communities, clubs, study groups, events,
--       projects, polls
-- =====================================================================
-- Membership lives in `conversation_members`, not in four near-identical
-- join tables. Every community / club / study group / project owns
-- exactly one conversation row, so "join the club" and "appear in the
-- club chat" are literally the same INSERT and can never disagree —
-- which is what chat_model.dart already assumes.
--
-- Events are the exception: RSVPing is not joining a thread, so events
-- get their own attendance table.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Communities  (department / batch / interest hubs)
-- ---------------------------------------------------------------------
create table if not exists public.communities (
  id              uuid primary key default public.uuid_generate_v7(),
  university_id   uuid not null references public.universities(id) on delete cascade,
  conversation_id uuid not null unique references public.conversations(id) on delete cascade,

  slug        citext not null,
  name        text   not null,
  description text   not null default '',
  cover_url   text,
  -- True for the auto-created "Computer Science" style department hubs
  -- that every student of that department is added to on signup.
  is_department boolean not null default false,
  -- Department communities are not joinable/leavable by hand.
  is_auto_join  boolean not null default false,
  is_active     boolean not null default true,

  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (university_id, slug)
);

create index if not exists communities_browse_idx
  on public.communities (university_id, is_department, name)
  where is_active;

create or replace trigger set_updated_at before update on public.communities
  for each row execute function public.tg_set_updated_at();


-- ---------------------------------------------------------------------
-- Clubs
-- ---------------------------------------------------------------------
create table if not exists public.clubs (
  id              uuid primary key default public.uuid_generate_v7(),
  university_id   uuid not null references public.universities(id) on delete cascade,
  conversation_id uuid not null unique references public.conversations(id) on delete cascade,

  slug             citext not null,
  name             text   not null,
  category         text   not null,          -- 'Technical', 'Cultural', …
  description      text   not null default '',
  meeting_schedule text,                     -- free text: 'Fri 5pm, Block 6'
  logo_url         text,
  lead_id          uuid references public.profiles(id) on delete set null,
  -- Denormalised for the club card; refreshed when lead_id changes.
  lead_name        text,
  -- Public clubs anyone can join; otherwise a lead must approve.
  requires_approval boolean not null default false,
  is_active        boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (university_id, slug)
);

create index if not exists clubs_browse_idx
  on public.clubs (university_id, category, name) where is_active;

create or replace trigger set_updated_at before update on public.clubs
  for each row execute function public.tg_set_updated_at();


-- Requests to join an approval-gated club or study group.
create table if not exists public.join_requests (
  id           uuid primary key default public.uuid_generate_v7(),
  source_type  public.group_source not null,
  source_id    uuid not null,
  -- Denormalised so approving is a single write into conversation_members.
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  message      text check (length(message) <= 300),
  state        text not null default 'pending'
                 check (state in ('pending', 'approved', 'rejected', 'withdrawn')),
  decided_by   uuid references public.profiles(id) on delete set null,
  decided_at   timestamptz,
  created_at   timestamptz not null default now()
);

create unique index if not exists join_requests_open_uniq
  on public.join_requests (source_type, source_id, user_id)
  where state = 'pending';

create index if not exists join_requests_inbox_idx
  on public.join_requests (conversation_id, created_at desc)
  where state = 'pending';


-- ---------------------------------------------------------------------
-- Study groups
-- ---------------------------------------------------------------------
create table if not exists public.study_groups (
  id              uuid primary key default public.uuid_generate_v7(),
  university_id   uuid not null references public.universities(id) on delete cascade,
  conversation_id uuid not null unique references public.conversations(id) on delete cascade,

  subject     text not null,
  title       text not null,
  description text not null default '',
  schedule    text,                     -- 'Tue & Thu, 7-9 pm'
  venue       text,
  host_id     uuid not null references public.profiles(id) on delete cascade,
  max_members smallint not null default 8 check (max_members between 2 and 100),

  is_open    boolean not null default true,   -- false = full or closed by host
  closed_at  timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists study_groups_browse_idx
  on public.study_groups (university_id, subject, created_at desc)
  where is_open;

create index if not exists study_groups_host_idx
  on public.study_groups (host_id, created_at desc);

create or replace trigger set_updated_at before update on public.study_groups
  for each row execute function public.tg_set_updated_at();


-- Close a study group the moment it fills up. `member_count` is
-- maintained on the conversation by the trigger in 0004, so this just
-- reacts to it — the cap is enforced in one place, not three.
create or replace function public.tg_study_group_capacity()
returns trigger
language plpgsql
as $$
begin
  update public.study_groups sg
     set is_open = (new.member_count < sg.max_members)
   where sg.conversation_id = new.id
     and sg.is_open <> (new.member_count < sg.max_members);
  return null;
end;
$$;

create or replace trigger study_group_capacity
  after update of member_count on public.conversations
  for each row execute function public.tg_study_group_capacity();


-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------
create table if not exists public.events (
  id            uuid primary key default public.uuid_generate_v7(),
  university_id uuid not null references public.universities(id) on delete cascade,
  -- Optional: big events get a discussion thread, small ones do not.
  conversation_id uuid unique references public.conversations(id) on delete set null,

  title       text not null,
  description text not null default '',
  category    text not null,             -- 'Tech', 'Cultural', 'Sports', …
  cover_url   text,

  -- Who is running it. Either a club or a student.
  organizer_club_id uuid references public.clubs(id) on delete set null,
  organizer_id      uuid references public.profiles(id) on delete set null,
  organizer_name    text not null,       -- denormalised for the list card

  starts_at timestamptz not null,
  ends_at   timestamptz,
  venue     text not null,

  max_participants integer check (max_participants > 0),
  -- Denormalised RSVP counters, maintained by the trigger below. The
  -- events list shows "142 going" on every card; counting rows per card
  -- would be the single most expensive query in the app.
  going_count      integer not null default 0,
  interested_count integer not null default 0,

  fee_amount   numeric(10, 2) not null default 0,
  fee_currency char(3) not null default 'INR',

  is_cancelled boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint events_time_order check (ends_at is null or ends_at > starts_at)
);

-- The events screen is "upcoming, soonest first", optionally by category.
create index if not exists events_upcoming_idx
  on public.events (university_id, starts_at)
  where not is_cancelled;

create index if not exists events_category_idx
  on public.events (university_id, category, starts_at)
  where not is_cancelled;

create index if not exists events_club_idx
  on public.events (organizer_club_id, starts_at desc);

create or replace trigger set_updated_at before update on public.events
  for each row execute function public.tg_set_updated_at();


create table if not exists public.event_rsvps (
  event_id   uuid not null references public.events(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  state      public.rsvp_state not null default 'going',
  checked_in_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

-- "Events I'm going to" on the profile screen.
create index if not exists event_rsvps_user_idx
  on public.event_rsvps (user_id, created_at desc);

create or replace trigger set_updated_at before update on public.event_rsvps
  for each row execute function public.tg_set_updated_at();


create or replace function public.tg_event_rsvp_counts()
returns trigger
language plpgsql
as $$
declare
  v_old public.rsvp_state := case when tg_op <> 'INSERT' then old.state end;
  v_new public.rsvp_state := case when tg_op <> 'DELETE' then new.state end;
begin
  if v_old is not distinct from v_new then
    return null;
  end if;

  update public.events set
    going_count = going_count
      + case when v_new = 'going' then 1 else 0 end
      - case when v_old = 'going' then 1 else 0 end,
    interested_count = interested_count
      + case when v_new = 'interested' then 1 else 0 end
      - case when v_old = 'interested' then 1 else 0 end
  where id = coalesce(new.event_id, old.event_id);

  return null;
end;
$$;

create or replace trigger event_rsvp_counts
  after insert or delete or update of state on public.event_rsvps
  for each row execute function public.tg_event_rsvp_counts();


-- ---------------------------------------------------------------------
-- Projects
-- ---------------------------------------------------------------------
create table if not exists public.projects (
  id            uuid primary key default public.uuid_generate_v7(),
  university_id uuid not null references public.universities(id) on delete cascade,
  conversation_id uuid unique references public.conversations(id) on delete set null,

  title       text not null,
  description text not null default '',
  stage       text not null default 'idea'
                check (stage in ('idea', 'planning', 'building', 'testing', 'launched', 'archived')),
  tech_stack   text[] not null default '{}',
  roles_needed text[] not null default '{}',

  owner_id   uuid not null references public.profiles(id) on delete cascade,
  owner_name text not null,
  team_size  integer not null default 1,
  applicant_count integer not null default 0,

  is_recruiting boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists projects_browse_idx
  on public.projects (university_id, created_at desc) where is_recruiting;

create index if not exists projects_tech_gin
  on public.projects using gin (tech_stack);

create index if not exists projects_roles_gin
  on public.projects using gin (roles_needed);

create index if not exists projects_owner_idx
  on public.projects (owner_id, created_at desc);

create or replace trigger set_updated_at before update on public.projects
  for each row execute function public.tg_set_updated_at();


create table if not exists public.project_applications (
  id         uuid primary key default public.uuid_generate_v7(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text,
  pitch      text check (length(pitch) <= 500),
  state      text not null default 'pending'
               check (state in ('pending', 'accepted', 'rejected', 'withdrawn')),
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists project_applications_open_uniq
  on public.project_applications (project_id, user_id)
  where state = 'pending';

create index if not exists project_applications_inbox_idx
  on public.project_applications (project_id, created_at desc);

create index if not exists project_applications_user_idx
  on public.project_applications (user_id, created_at desc);


create or replace function public.tg_project_applicant_count()
returns trigger
language plpgsql
as $$
begin
  update public.projects
     set applicant_count = (
       select count(*) from public.project_applications
       where project_id = coalesce(new.project_id, old.project_id)
         and state = 'pending'
     )
   where id = coalesce(new.project_id, old.project_id);
  return null;
end;
$$;

create or replace trigger project_applicant_count
  after insert or delete or update of state on public.project_applications
  for each row execute function public.tg_project_applicant_count();


-- ---------------------------------------------------------------------
-- Polls
-- ---------------------------------------------------------------------
create table if not exists public.polls (
  id            uuid primary key default public.uuid_generate_v7(),
  university_id uuid not null references public.universities(id) on delete cascade,
  -- A poll can be campus-wide (null) or scoped to one thread.
  conversation_id uuid references public.conversations(id) on delete cascade,

  question    text not null check (length(question) between 3 and 300),
  author_id   uuid not null references public.profiles(id) on delete cascade,
  author_name text not null default 'A student',
  is_anonymous   boolean not null default false,
  allow_multiple boolean not null default false,
  total_votes integer not null default 0,

  closes_at  timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists polls_feed_idx
  on public.polls (university_id, created_at desc);

create index if not exists polls_conversation_idx
  on public.polls (conversation_id, created_at desc)
  where conversation_id is not null;


create table if not exists public.poll_options (
  id       uuid primary key default public.uuid_generate_v7(),
  poll_id  uuid not null references public.polls(id) on delete cascade,
  position smallint not null,
  text     text not null check (length(text) between 1 and 120),
  -- Denormalised so rendering a poll is one query, not one per option.
  vote_count integer not null default 0,
  unique (poll_id, position)
);

create index if not exists poll_options_poll_idx on public.poll_options (poll_id, position);


create table if not exists public.poll_votes (
  poll_id    uuid not null references public.polls(id) on delete cascade,
  option_id  uuid not null references public.poll_options(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, user_id, option_id)
);

create index if not exists poll_votes_option_idx on public.poll_votes (option_id);


create or replace function public.tg_poll_vote_counts()
returns trigger
language plpgsql
as $$
declare
  v_poll   uuid := coalesce(new.poll_id, old.poll_id);
  v_option uuid := coalesce(new.option_id, old.option_id);
  v_delta  int  := case when tg_op = 'INSERT' then 1 else -1 end;
begin
  update public.poll_options set vote_count = vote_count + v_delta where id = v_option;
  -- total_votes counts distinct voters, not ticks, so recount it. Polls
  -- are small and low-traffic; correctness beats cleverness here.
  update public.polls
     set total_votes = (select count(distinct user_id) from public.poll_votes where poll_id = v_poll)
   where id = v_poll;
  return null;
end;
$$;

create or replace trigger poll_vote_counts
  after insert or delete on public.poll_votes
  for each row execute function public.tg_poll_vote_counts();


-- Single-choice polls: replace the previous vote instead of erroring.
create or replace function public.tg_poll_single_choice()
returns trigger
language plpgsql
as $$
begin
  if not (select allow_multiple from public.polls where id = new.poll_id) then
    delete from public.poll_votes
     where poll_id = new.poll_id and user_id = new.user_id and option_id <> new.option_id;
  end if;
  return new;
end;
$$;

create or replace trigger poll_single_choice before insert on public.poll_votes
  for each row execute function public.tg_poll_single_choice();


-- ---------------------------------------------------------------------
-- Bookmarks  (bookmarks_screen.dart)
-- ---------------------------------------------------------------------
-- Polymorphic on purpose: a student can save an event, a project, a poll
-- or another student. Four bookmark tables to gain a foreign key is not
-- a trade worth making — the cleanup job prunes dangling targets.
create table if not exists public.bookmarks (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('event', 'project', 'poll', 'profile', 'club', 'study_group')),
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, target_type, target_id)
);

create index if not exists bookmarks_recent_idx
  on public.bookmarks (user_id, created_at desc);
