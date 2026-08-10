-- =====================================================================
-- 0012  What the Flutter client needs that 0001-0011 did not expose
-- =====================================================================
-- Everything here came out of wiring the app up. Each item exists because
-- a screen needs it and the existing surface cannot express it — not
-- because the schema was wrong.
--
-- 1. `projects.cover_url`. Events, clubs and communities all had an image
--    column; projects did not, so a project card had nothing to render.
--
-- 2. `clear_my_history()`. "Clear messages" hides history from one
--    student. That is `conversation_members.visible_from_seq`, which is
--    deliberately NOT in the column grants in 0008 — a client that could
--    move it freely could also unhide history from before it joined.
--
-- 3. `clear_my_notifications()`. DELETE is revoked on `notifications`
--    (0008), so "Clear all" needs a function.
--
-- 4. `create_poll()`. A poll and its options are two tables. Two client
--    inserts leave a window where a poll exists with nothing to vote on,
--    and the second insert can fail.
--
-- 5. Realtime for polls and events. 0008 publishes messages,
--    conversations and notifications. The Polls and Events screens are
--    live too, and a publication is the only way to say so.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Project cover images  (campus-assets bucket)
-- ---------------------------------------------------------------------
alter table public.projects add column if not exists cover_url text;

-- No column-level revoke on `projects`, so `projects_owner_update` already
-- covers this; stated here so the grant is not a mystery later.
comment on column public.projects.cover_url is
  'Public URL in the campus-assets bucket. Uploaded by the owner; see StorageRepository.uploadCampusAsset.';


-- ---------------------------------------------------------------------
-- 2. clear_my_history
-- ---------------------------------------------------------------------
-- Hides everything said so far from the caller only. The other members
-- keep their copy — this is "clear my chat", not "delete the thread".
--
-- Only ever moves the pointer forward: greatest() so a stale request from
-- a slow device cannot un-hide messages the student already cleared.
create or replace function public.clear_my_history(p_conversation_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_last bigint;
  v_from bigint;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select last_seq into v_last from public.conversations where id = p_conversation_id;
  if v_last is null then
    raise exception 'Conversation not found' using errcode = 'no_data_found';
  end if;

  update public.conversation_members
     set visible_from_seq = greatest(visible_from_seq, v_last),
         last_read_seq    = greatest(last_read_seq, v_last),
         last_delivered_seq = greatest(last_delivered_seq, v_last)
   where conversation_id = p_conversation_id and user_id = v_me and left_at is null
  returning visible_from_seq into v_from;

  if v_from is null then
    raise exception 'You are not a member of this conversation' using errcode = '42501';
  end if;

  return v_from;
end;
$$;


-- ---------------------------------------------------------------------
-- 3. clear_my_notifications
-- ---------------------------------------------------------------------
create or replace function public.clear_my_notifications()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_n  integer;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- Partition-pruned: `notifications` is hash partitioned on user_id.
  delete from public.notifications where user_id = v_me;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;


-- ---------------------------------------------------------------------
-- 4. create_poll
-- ---------------------------------------------------------------------
-- Returns the poll with its options embedded, shaped like the
-- `polls(*, poll_options(*))` select the feed uses, so the client maps one
-- row type either way.
create or replace function public.create_poll(
  p_question       text,
  p_options        text[],
  p_conversation_id uuid default null,
  p_allow_multiple boolean default false,
  p_closes_at      timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me     uuid := auth.uid();
  v_uni    uuid;
  v_name   text;
  v_poll   public.polls%rowtype;
  v_option text;
  v_pos    smallint := 0;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if coalesce(array_length(p_options, 1), 0) < 2 then
    raise exception 'A poll needs at least two options' using errcode = '22023';
  end if;
  if array_length(p_options, 1) > 10 then
    raise exception 'A poll can have at most ten options' using errcode = '22023';
  end if;
  if not public.check_rate_limit(v_me, 'create_poll', 10, interval '1 day') then
    raise exception 'You have created too many polls today' using errcode = '53400';
  end if;

  select university_id, full_name into v_uni, v_name
  from public.profiles where id = v_me and deleted_at is null;
  if v_uni is null then
    raise exception 'Profile not found' using errcode = 'no_data_found';
  end if;

  -- A thread-scoped poll is only allowed in a thread the caller belongs to.
  if p_conversation_id is not null
     and not public.is_conversation_member(p_conversation_id, v_me) then
    raise exception 'You are not a member of this conversation' using errcode = '42501';
  end if;

  insert into public.polls (
    university_id, conversation_id, question, author_id, author_name,
    allow_multiple, closes_at
  ) values (
    v_uni, p_conversation_id, p_question, v_me, coalesce(v_name, 'A student'),
    p_allow_multiple, p_closes_at
  )
  returning * into v_poll;

  foreach v_option in array p_options
  loop
    if length(trim(v_option)) > 0 then
      insert into public.poll_options (poll_id, position, text)
      values (v_poll.id, v_pos, trim(v_option));
      v_pos := v_pos + 1;
    end if;
  end loop;

  if v_pos < 2 then
    raise exception 'A poll needs at least two non-empty options' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'id',            v_poll.id,
    'question',      v_poll.question,
    'author_id',     v_poll.author_id,
    'author_name',   v_poll.author_name,
    'allow_multiple',v_poll.allow_multiple,
    'total_votes',   v_poll.total_votes,
    'closes_at',     v_poll.closes_at,
    'created_at',    v_poll.created_at,
    'poll_options',  (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'position', o.position, 'text', o.text,
        'vote_count', o.vote_count
      ) order by o.position), '[]'::jsonb)
      from public.poll_options o where o.poll_id = v_poll.id
    )
  );
end;
$$;


-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke all on function public.clear_my_history(uuid) from public, anon;
revoke all on function public.clear_my_notifications() from public, anon;
revoke all on function public.create_poll(text, text[], uuid, boolean, timestamptz) from public, anon;

grant execute on function public.clear_my_history(uuid) to authenticated;
grant execute on function public.clear_my_notifications() to authenticated;
grant execute on function public.create_poll(text, text[], uuid, boolean, timestamptz) to authenticated;


-- ---------------------------------------------------------------------
-- 5. Realtime: polls and events
-- ---------------------------------------------------------------------
-- Both respect RLS, so a student only receives rows they could have
-- SELECTed: `polls_read` limits polls to their campus (and, for
-- thread-scoped polls, to threads they belong to), `events_read` to their
-- campus.
--
-- `poll_votes` is deliberately NOT published. A client can only read its
-- own ballot, so publishing it would leak nothing — but it would also
-- announce every vote to every subscriber's filter for no gain, since
-- tallies arrive through poll_options.vote_count.
do $$ begin
  alter publication supabase_realtime add table public.polls;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.poll_options;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.events;
exception when duplicate_object then null; end $$;

-- REPLICA IDENTITY FULL so an UPDATE carries the old row too — without it a
-- vote_count change arrives with only the primary key and the new value,
-- and none of these are partitioned, so the parent is the whole story.
alter table public.polls        replica identity full;
alter table public.poll_options replica identity full;
alter table public.events       replica identity full;
