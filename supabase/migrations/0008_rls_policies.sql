-- =====================================================================
-- 0008  Row Level Security
-- =====================================================================
-- With Supabase the Flutter client talks to Postgres over PostgREST with
-- the student's own JWT. RLS is therefore not defence in depth — it IS
-- the authorisation layer. Anything not covered by a policy here is
-- reachable by anyone who opens the app and reads the anon key out of
-- the APK.
--
-- Shape of every policy below: start from "nothing is visible", then add
-- back exactly what this student is entitled to.
--
-- Recursion note: policies on conversation_members must not query
-- conversation_members, or Postgres recurses. That is why membership
-- tests go through the SECURITY DEFINER helpers from 0007.
-- =====================================================================

-- Postgres has no CREATE OR REPLACE POLICY, so drop what this file owns
-- before recreating it. Keeps the migration re-runnable during dev.
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies where schemaname = 'public'
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;


alter table public.universities            enable row level security;
alter table public.programs                enable row level security;
alter table public.tags                    enable row level security;
alter table public.profiles                enable row level security;
alter table public.user_presence           enable row level security;
alter table public.badges                  enable row level security;
alter table public.profile_badges          enable row level security;
alter table public.verification_requests   enable row level security;
alter table public.user_devices            enable row level security;
alter table public.connections             enable row level security;
alter table public.blocks                  enable row level security;
alter table public.profile_views           enable row level security;
alter table public.conversations           enable row level security;
alter table public.conversation_members    enable row level security;
alter table public.messages                enable row level security;
alter table public.message_attachments     enable row level security;
alter table public.message_reactions       enable row level security;
alter table public.upload_tickets          enable row level security;
alter table public.communities             enable row level security;
alter table public.clubs                   enable row level security;
alter table public.join_requests           enable row level security;
alter table public.study_groups            enable row level security;
alter table public.events                  enable row level security;
alter table public.event_rsvps             enable row level security;
alter table public.projects                enable row level security;
alter table public.project_applications    enable row level security;
alter table public.polls                   enable row level security;
alter table public.poll_options            enable row level security;
alter table public.poll_votes              enable row level security;
alter table public.bookmarks               enable row level security;
alter table public.notifications           enable row level security;
alter table public.notification_settings   enable row level security;
alter table public.reports                 enable row level security;
alter table public.moderation_actions      enable row level security;
alter table public.rate_limits             enable row level security;
alter table public.audit_log               enable row level security;


-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
-- The caller's campus. STABLE + SECURITY DEFINER so it is evaluated once
-- per statement and does not itself trip profiles' RLS.
create or replace function public.my_university()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select university_id from public.profiles where id = auth.uid();
$$;

create or replace function public.is_moderator(p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profile_badges
    where profile_id = p_user and badge_slug in ('moderator', 'admin')
  );
$$;


-- ---------------------------------------------------------------------
-- Reference data — readable by any signed-in student, writable by none
-- ---------------------------------------------------------------------
create policy universities_read on public.universities
  for select to authenticated using (is_active);

create policy programs_read on public.programs
  for select to authenticated using (true);

create policy tags_read on public.tags
  for select to authenticated using (is_active);

create policy badges_read on public.badges
  for select to authenticated using (true);


-- ---------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------
-- Always your own row, in full. Other students only if they are on your
-- campus, active, discoverable, and neither of you has blocked the other.
create policy profiles_read_self on public.profiles
  for select to authenticated using (id = auth.uid());

create policy profiles_read_campus on public.profiles
  for select to authenticated using (
    id <> auth.uid()
    and university_id = public.my_university()
    and deleted_at is null
    and deactivated_at is null
    and (discoverable or public.are_connected(auth.uid(), id))
    and not public.is_blocked_either_way(auth.uid(), id)
  );

-- A student edits their own profile. `using` gates which rows they may
-- touch; `with check` gates what the row may become — without it they
-- could hand themselves a different university_id on the way out.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Trust, verification and moderation counters are set by triggers and
-- back-office code, never by the app. Column-level privileges are the
-- only thing that can express this; an RLS policy cannot.
revoke update on public.profiles from authenticated;
grant update (
  full_name, username, gender, date_of_birth, phone_e164,
  bio, campus_status, avatar_path, avatar_url,
  interests, languages, looking_for, program_id,
  hide_department, hide_year, hide_looking_for, hide_active_status,
  discoverable, allow_dm_from_anyone,
  onboarding_completed_at, deactivated_at
) on public.profiles to authenticated;


-- ---------------------------------------------------------------------
-- Presence
-- ---------------------------------------------------------------------
create policy presence_read on public.user_presence
  for select to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = user_presence.user_id
        and p.university_id = public.my_university()
        and not p.hide_active_status
        and not public.is_blocked_either_way(auth.uid(), p.id)
    )
  );

create policy presence_write_self on public.user_presence
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- Badges, verification, devices
-- ---------------------------------------------------------------------
create policy profile_badges_read on public.profile_badges
  for select to authenticated using (true);

create policy verification_own on public.verification_requests
  for all to authenticated
  using (profile_id = auth.uid() or public.is_moderator())
  with check (profile_id = auth.uid());

create policy devices_own on public.user_devices
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- Connections
-- ---------------------------------------------------------------------
create policy connections_read on public.connections
  for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

create policy connections_send on public.connections
  for insert to authenticated
  with check (
    requester_id = auth.uid()
    and addressee_id <> auth.uid()
    and state = 'pending'
    and not public.is_blocked_either_way(auth.uid(), addressee_id)
    and exists (
      select 1 from public.profiles p
      where p.id = addressee_id
        and p.university_id = public.my_university()
        and p.deleted_at is null
    )
    -- check_my_rate_limit, not check_rate_limit: see the comment on the
    -- latter in 0006. A policy runs with the caller's privileges, so the
    -- version taking an arbitrary user id must stay unreachable.
    and public.check_my_rate_limit('connect_request', 40, interval '1 day')
  );

-- Either side can move an existing request along (accept / decline /
-- withdraw). The state machine itself is enforced by the trigger below.
create policy connections_respond on public.connections
  for update to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid())
  with check (requester_id = auth.uid() or addressee_id = auth.uid());


-- Only the addressee may accept. Letting the requester write
-- state='accepted' would turn a request into a connection unilaterally,
-- which no `with check` expression can prevent on its own.
create or replace function public.tg_connection_transition()
returns trigger
language plpgsql
as $$
begin
  if new.state = old.state then
    return new;
  end if;

  -- Legal transitions:
  --   pending  -> accepted | declined   (addressee only)
  --   pending  -> withdrawn             (requester only)
  --   pending  -> cancelled             (block / moderation)
  --   accepted -> cancelled             (either party disconnects, or a block)
  if old.state = 'pending' then
    if new.state in ('accepted', 'declined') and auth.uid() is distinct from old.addressee_id then
      raise exception 'Only the recipient can accept or decline a request' using errcode = '42501';
    end if;
    if new.state = 'withdrawn' and auth.uid() is distinct from old.requester_id then
      raise exception 'Only the sender can withdraw a request' using errcode = '42501';
    end if;

  elsif old.state = 'accepted' then
    -- Disconnecting is the only way out of an accepted connection. This
    -- branch has to exist or blocking someone you are connected with
    -- fails outright: tg_block_severs_connection cancels the connection,
    -- and an "already answered" guard would abort the whole INSERT into
    -- blocks — the case blocking matters most in.
    if new.state <> 'cancelled' then
      raise exception 'An accepted connection can only be cancelled' using errcode = '22023';
    end if;

  else
    -- declined / withdrawn / cancelled are terminal.
    raise exception 'This request has already been answered' using errcode = '22023';
  end if;

  new.responded_at := now();
  return new;
end;
$$;

create or replace trigger connection_transition
  before update of state on public.connections
  for each row execute function public.tg_connection_transition();


-- ---------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------
-- Deliberately no read access to rows where you are the blocked party:
-- being able to query "who blocked me" is a harassment vector.
create policy blocks_own on public.blocks
  for all to authenticated
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());


-- ---------------------------------------------------------------------
-- Profile views
-- ---------------------------------------------------------------------
create policy profile_views_read on public.profile_views
  for select to authenticated using (viewed_id = auth.uid());

create policy profile_views_write on public.profile_views
  for insert to authenticated with check (viewer_id = auth.uid());

create policy profile_views_bump on public.profile_views
  for update to authenticated
  using (viewer_id = auth.uid()) with check (viewer_id = auth.uid());


-- ---------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------
create policy conversations_read on public.conversations
  for select to authenticated using (public.is_conversation_member(id));

-- Group threads are created together with their club/community by
-- back-office code; DMs by get_or_create_direct_conversation(). Neither
-- path is a plain client INSERT, so there is no insert policy at all.

create policy conversation_members_read on public.conversation_members
  for select to authenticated using (public.is_conversation_member(conversation_id));

-- A member may only edit their own row, and only the read/notification
-- columns — role escalation is not on the table.
create policy conversation_members_update_self on public.conversation_members
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke update on public.conversation_members from authenticated;
grant update (last_read_seq, last_delivered_seq, is_pinned, muted_until, notify_level)
  on public.conversation_members to authenticated;


-- Messages are readable by members only, and only from the point they
-- joined. Writes go exclusively through send_message() / delete_message().
create policy messages_read on public.messages
  for select to authenticated using (
    public.is_conversation_member(conversation_id)
    and seq > coalesce((
      select cm.visible_from_seq from public.conversation_members cm
      where cm.conversation_id = messages.conversation_id and cm.user_id = auth.uid()
    ), 0)
  );

revoke insert, update, delete on public.messages from authenticated, anon;


create policy attachments_read on public.message_attachments
  for select to authenticated using (public.is_conversation_member(conversation_id));

revoke insert, update, delete on public.message_attachments from authenticated, anon;


create policy reactions_read on public.message_reactions
  for select to authenticated using (public.is_conversation_member(conversation_id));

create policy reactions_write on public.message_reactions
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_conversation_member(conversation_id));

create policy reactions_delete on public.message_reactions
  for delete to authenticated using (user_id = auth.uid());


create policy upload_tickets_own on public.upload_tickets
  for select to authenticated using (user_id = auth.uid());

revoke insert, update, delete on public.upload_tickets from authenticated, anon;


-- ---------------------------------------------------------------------
-- Campus hub — browse anything on your campus
-- ---------------------------------------------------------------------
create policy communities_read on public.communities
  for select to authenticated using (university_id = public.my_university() and is_active);

create policy clubs_read on public.clubs
  for select to authenticated using (university_id = public.my_university() and is_active);

create policy study_groups_read on public.study_groups
  for select to authenticated using (university_id = public.my_university());

-- No INSERT policy: study_groups.conversation_id is NOT NULL and the
-- client cannot create a conversation, so a direct insert could never
-- succeed anyway. Creation goes through create_study_group(), which
-- makes the group, its thread and the host's membership atomically.

create policy study_groups_host_update on public.study_groups
  for update to authenticated using (host_id = auth.uid()) with check (host_id = auth.uid());

create policy join_requests_own on public.join_requests
  for select to authenticated
  using (user_id = auth.uid() or public.conversation_role(conversation_id) in ('owner', 'admin'));

create policy join_requests_create on public.join_requests
  for insert to authenticated with check (user_id = auth.uid());

create policy join_requests_decide on public.join_requests
  for update to authenticated
  using (user_id = auth.uid() or public.conversation_role(conversation_id) in ('owner', 'admin'))
  with check (true);


create policy events_read on public.events
  for select to authenticated using (university_id = public.my_university());

create policy events_create on public.events
  for insert to authenticated
  with check (
    organizer_id = auth.uid()
    and university_id = public.my_university()
    -- New accounts cannot spam events into the campus feed.
    and (select trust_level from public.profiles where id = auth.uid()) = 'trusted'
  );

create policy events_owner_update on public.events
  for update to authenticated
  using (organizer_id = auth.uid()) with check (organizer_id = auth.uid());

-- Counts are public; who is going is not. The events screen shows
-- going_count from the denormalised column, so this policy losing the
-- roster costs nothing.
create policy event_rsvps_own on public.event_rsvps
  for all to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.events e where e.id = event_id and e.organizer_id = auth.uid())
  )
  with check (user_id = auth.uid());


create policy projects_read on public.projects
  for select to authenticated using (university_id = public.my_university());

create policy projects_create on public.projects
  for insert to authenticated
  with check (owner_id = auth.uid() and university_id = public.my_university());

create policy projects_owner_update on public.projects
  for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy project_apps_visible on public.project_applications
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid())
  );

create policy project_apps_create on public.project_applications
  for insert to authenticated with check (user_id = auth.uid());

create policy project_apps_decide on public.project_applications
  for update to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid())
  )
  with check (true);


create policy polls_read on public.polls
  for select to authenticated using (
    university_id = public.my_university()
    and (conversation_id is null or public.is_conversation_member(conversation_id))
  );

create policy polls_create on public.polls
  for insert to authenticated
  with check (author_id = auth.uid() and university_id = public.my_university());

create policy poll_options_read on public.poll_options
  for select to authenticated
  using (exists (select 1 from public.polls p where p.id = poll_id));

create policy poll_options_create on public.poll_options
  for insert to authenticated
  with check (exists (select 1 from public.polls p where p.id = poll_id and p.author_id = auth.uid()));

-- You can see your own ballot and nothing else. Results come from the
-- denormalised vote_count, so anonymity actually holds.
create policy poll_votes_own on public.poll_votes
  for select to authenticated using (user_id = auth.uid());

create policy poll_votes_cast on public.poll_votes
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.polls p
      where p.id = poll_id and (p.closes_at is null or p.closes_at > now())
    )
  );

create policy poll_votes_retract on public.poll_votes
  for delete to authenticated using (user_id = auth.uid());


create policy bookmarks_own on public.bookmarks
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------
create policy notifications_own on public.notifications
  for select to authenticated using (user_id = auth.uid());

-- Only the "mark as read" column is writable from the app.
create policy notifications_mark_read on public.notifications
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke insert, delete on public.notifications from authenticated, anon;
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

create policy notification_settings_own on public.notification_settings
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- Moderation
-- ---------------------------------------------------------------------
create policy reports_create on public.reports
  for insert to authenticated
  with check (
    reporter_id = auth.uid()
    and public.check_my_rate_limit('report', 10, interval '1 day')
  );

create policy reports_read_own on public.reports
  for select to authenticated using (reporter_id = auth.uid() or public.is_moderator());

create policy reports_moderate on public.reports
  for update to authenticated using (public.is_moderator()) with check (public.is_moderator());

-- A student can see what was done to them; only moderators see the rest.
create policy moderation_read on public.moderation_actions
  for select to authenticated using (subject_id = auth.uid() or public.is_moderator());

revoke insert, update, delete on public.moderation_actions from authenticated, anon;

-- Rate limit counters and the audit log are service-role only. No
-- policies at all means RLS denies everything to `authenticated`.
revoke all on public.rate_limits from authenticated, anon;
revoke all on public.audit_log   from authenticated, anon;


-- ---------------------------------------------------------------------
-- Partitions: RLS does NOT inherit
-- ---------------------------------------------------------------------
-- `ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY` sets the flag on
-- the parent only. Query through the parent and the parent's policies
-- apply — but a partition reached DIRECTLY has no RLS at all.
--
-- That is not theoretical: PostgREST exposes every table in `public`, so
-- `messages_p3` is a valid endpoint. Without this loop, any student
-- holding the app's anon key can read every private message in the
-- system by asking for the partition instead of the table. Verified:
-- an outsider got 0 rows from `public.messages` and all of them from
-- `public.messages_p0..p15`.
--
-- RLS on with no policies of its own = deny everything, which is exactly
-- right for a partition: nothing should ever address one directly.
-- Access through the parent keeps using the parent's policies.
--
-- ANY PARTITION ADDED LATER MUST BE ENABLED THE SAME WAY.
do $$
declare r record;
begin
  for r in
    select c.oid::regclass as part
    from pg_class c
    join pg_inherits i on i.inhrelid = c.oid
    where i.inhparent in ('public.messages'::regclass,
                          'public.message_attachments'::regclass,
                          'public.message_reactions'::regclass,
                          'public.notifications'::regclass)
  loop
    execute format('alter table %s enable row level security', r.part);
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------
-- Supabase Realtime respects RLS on these, so a student only receives
-- rows they could have SELECTed. Presence and typing are NOT published:
-- they go over the Node chat server's websocket instead (see DATABASE.md).
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.conversations;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null; end $$;

-- Without this, logical replication reports changes to a partitioned
-- table under the PARTITION's name — `messages_p3`, not `messages`. The
-- Flutter client subscribes to `public:messages` and would receive
-- nothing at all. Publishing via the partition root makes every change
-- arrive under the parent name, which is what the app listens for.
alter publication supabase_realtime set (publish_via_partition_root = true);

-- REPLICA IDENTITY FULL makes the old row available on UPDATE/DELETE, so
-- a client can tell an edit from a delete without re-fetching.
--
-- Logical decoding reads the *partitions*, not the parent, so setting
-- this on public.messages alone would silently do nothing. Every current
-- and future partition needs it — the loop covers the ones created in
-- 0004, and any partition added later must repeat this.
alter table public.conversations replica identity full;

do $$
declare r record;
begin
  for r in
    select c.oid::regclass as part
    from pg_class c
    join pg_inherits i on i.inhrelid = c.oid
    where i.inhparent in ('public.messages'::regclass,
                          'public.notifications'::regclass)
  loop
    execute format('alter table %s replica identity full', r.part);
  end loop;
end $$;
