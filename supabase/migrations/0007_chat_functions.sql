-- =====================================================================
-- 0007  Chat RPCs
-- =====================================================================
-- The client never INSERTs into `messages` directly. Allocating a seq,
-- checking the block list, consuming the upload ticket and refreshing
-- the conversation preview have to happen as one atomic unit, and a
-- function is the only place that can be guaranteed.
--
-- All of these are SECURITY DEFINER — they bypass RLS by design and do
-- their own authorisation, which is stated explicitly at the top of each.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Membership helper (used by RLS in 0008; kept out of `public` reach)
-- ---------------------------------------------------------------------
create or replace function public.is_conversation_member(p_conversation_id uuid, p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = p_conversation_id
      and user_id = p_user
      and left_at is null
  );
$$;


create or replace function public.conversation_role(p_conversation_id uuid, p_user uuid default auth.uid())
returns public.member_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.conversation_members
  where conversation_id = p_conversation_id and user_id = p_user and left_at is null;
$$;


-- ---------------------------------------------------------------------
-- get_or_create_direct_conversation
-- ---------------------------------------------------------------------
-- Authorisation: caller must not be blocked by, and must be connected to
-- (or explicitly open to DMs from), the other student.
--
-- The ON CONFLICT on direct_key is what makes this safe when the user
-- double-taps "Message" and two requests race.
create or replace function public.get_or_create_direct_conversation(p_other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_key   text;
  v_conv  uuid;
  v_other public.profiles%rowtype;
  v_uni   uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if v_me = p_other_user then
    raise exception 'Cannot open a chat with yourself' using errcode = '22023';
  end if;

  select * into v_other from public.profiles
   where id = p_other_user and deleted_at is null and deactivated_at is null;
  if not found then
    raise exception 'That student is no longer on Campus Connect' using errcode = 'no_data_found';
  end if;

  select university_id into v_uni from public.profiles where id = v_me;
  if v_uni is distinct from v_other.university_id then
    raise exception 'You can only message students from your own campus' using errcode = '42501';
  end if;

  if public.is_blocked_either_way(v_me, p_other_user) then
    raise exception 'This chat is not available' using errcode = '42501';
  end if;

  if not v_other.allow_dm_from_anyone and not public.are_connected(v_me, p_other_user) then
    raise exception 'Send a connection request first' using errcode = '42501';
  end if;

  v_key := least(v_me::text, p_other_user::text) || ':' || greatest(v_me::text, p_other_user::text);

  select id into v_conv from public.conversations where direct_key = v_key;
  if found then
    -- Re-open it if either side had left.
    update public.conversation_members
       set left_at = null
     where conversation_id = v_conv and user_id in (v_me, p_other_user) and left_at is not null;
    return v_conv;
  end if;

  insert into public.conversations (university_id, type, direct_key, created_by)
  values (v_uni, 'direct', v_key, v_me)
  -- The index being inferred here (conversations_direct_key_uniq) is
  -- PARTIAL, so its predicate has to be repeated: Postgres will not match
  -- a partial index from the column list alone.
  on conflict (direct_key) where direct_key is not null do nothing
  returning id into v_conv;

  if v_conv is null then
    -- Lost the race; the other transaction created it.
    select id into v_conv from public.conversations where direct_key = v_key;
    return v_conv;
  end if;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (v_conv, v_me, 'member'), (v_conv, p_other_user, 'member')
  on conflict do nothing;

  return v_conv;
end;
$$;


-- ---------------------------------------------------------------------
-- send_message
-- ---------------------------------------------------------------------
-- Authorisation: caller must be an active member of the conversation,
-- not suspended, not blocked (DMs), and within the rate limit.
--
-- Idempotent on (conversation_id, p_client_msg_id): a retry over flaky
-- campus wifi returns the original message instead of posting a second
-- copy. The client must generate the id once, before the first attempt.
--
-- p_attachments is a JSON array of objects shaped like:
--   { "object_path": "...", "width": 1024, "height": 768,
--     "blurhash": "...", "thumb_path": "...", "page_count": 12 }
-- Everything trustworthy (kind, size, mime, filename) comes from the
-- matching upload_tickets row, never from the client payload here.
create or replace function public.send_message(
  p_conversation_id uuid,
  p_body            text default null,
  p_kind            public.message_kind default 'text',
  p_client_msg_id   uuid default null,
  p_reply_to_id     uuid default null,
  p_attachments     jsonb default '[]'::jsonb,
  p_mentions        uuid[] default '{}'
) returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me      uuid := auth.uid();
  v_client  uuid := coalesce(p_client_msg_id, gen_random_uuid());
  v_conv    public.conversations%rowtype;
  v_msg     public.messages%rowtype;
  v_seq     bigint;
  v_att     jsonb;
  v_ticket  public.upload_tickets%rowtype;
  v_count   smallint := 0;
  v_preview text;
  v_trust   public.trust_level;
  v_other   uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- 1. Idempotency — check before doing anything with side effects.
  select * into v_msg from public.messages
   where conversation_id = p_conversation_id and client_msg_id = v_client;
  if found then
    return v_msg;
  end if;

  -- 2. Membership
  if not public.is_conversation_member(p_conversation_id, v_me) then
    raise exception 'You are not a member of this conversation' using errcode = '42501';
  end if;

  -- 3. Sender standing
  select trust_level into v_trust from public.profiles where id = v_me;
  if v_trust in ('suspended', 'restricted') then
    raise exception 'Your account cannot send messages right now' using errcode = '42501';
  end if;

  -- 4. Rate limit: 30 messages/minute is far above human typing speed
  --    and far below what a script would want.
  if not public.check_rate_limit(v_me, 'send_message', 30, interval '1 minute') then
    raise exception 'You are sending messages too quickly. Wait a moment.' using errcode = '53400';
  end if;

  select * into v_conv from public.conversations where id = p_conversation_id;
  if v_conv.is_locked then
    raise exception 'This conversation is read-only' using errcode = '42501';
  end if;

  -- 5. DM gate. Re-checked on every send, not just at creation: if the
  --    two students disconnect or one blocks the other, the thread goes
  --    read-only immediately rather than at next app launch.
  if v_conv.type = 'direct' then
    select user_id into v_other from public.conversation_members
     where conversation_id = p_conversation_id and user_id <> v_me limit 1;

    if public.is_blocked_either_way(v_me, v_other) then
      raise exception 'This chat is not available' using errcode = '42501';
    end if;
    if not public.are_connected(v_me, v_other)
       and not (select allow_dm_from_anyone from public.profiles where id = v_other) then
      raise exception 'You are no longer connected with this student' using errcode = '42501';
    end if;
  end if;

  -- 6. Allocate the sequence number. This UPDATE takes a row lock on the
  --    conversation, which serialises concurrent sends in that thread —
  --    the reason seq can never be duplicated or reordered.
  update public.conversations
     set last_seq = last_seq + 1
   where id = p_conversation_id
  returning last_seq into v_seq;

  -- 7. Insert
  insert into public.messages (
    conversation_id, seq, sender_id, kind, body,
    reply_to_id, client_msg_id, mentions
  ) values (
    p_conversation_id, v_seq, v_me, p_kind, nullif(trim(coalesce(p_body, '')), ''),
    p_reply_to_id, v_client, coalesce(p_mentions, '{}')
  )
  returning * into v_msg;

  -- 8. Attach files. Each one must be backed by an unconsumed ticket
  --    this user created for this conversation — that is what stops a
  --    client claiming someone else's uploaded object.
  for v_att in select * from jsonb_array_elements(coalesce(p_attachments, '[]'::jsonb))
  loop
    select * into v_ticket from public.upload_tickets
     where object_path = (v_att ->> 'object_path')
       and user_id = v_me
       and conversation_id = p_conversation_id
       and consumed_at is null
       and expires_at > now()
     for update;

    if not found then
      raise exception 'Upload % is not valid or has expired', (v_att ->> 'object_path')
        using errcode = '42501';
    end if;

    insert into public.message_attachments (
      conversation_id, message_id, kind, bucket, object_path,
      file_name, mime_type, size_bytes,
      width, height, blurhash, thumb_path, page_count
    ) values (
      p_conversation_id, v_msg.id, v_ticket.kind, v_ticket.bucket, v_ticket.object_path,
      v_ticket.file_name, v_ticket.mime_type, v_ticket.declared_size,
      (v_att ->> 'width')::int, (v_att ->> 'height')::int,
      v_att ->> 'blurhash', v_att ->> 'thumb_path', (v_att ->> 'page_count')::int
    );

    update public.upload_tickets set consumed_at = now() where id = v_ticket.id;
    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    update public.messages set attachment_count = v_count
     where conversation_id = p_conversation_id and seq = v_seq
    returning * into v_msg;
  elsif p_kind in ('photo', 'document') then
    raise exception 'An attachment message needs at least one file' using errcode = '22023';
  end if;

  -- 9. Refresh the chat-list preview. Mirrors Message.preview in
  --    chat_model.dart so the list and the bubble agree.
  v_preview := case
    when v_msg.kind = 'photo'    then '📷 Photo'
    when v_msg.kind = 'document' then '📄 ' ||
      coalesce((select file_name from public.message_attachments
                 where conversation_id = p_conversation_id and message_id = v_msg.id limit 1), 'Document')
    else left(coalesce(v_msg.body, ''), 120)
  end;

  update public.conversations
     set last_message_at        = v_msg.created_at,
         last_message_preview   = v_preview,
         last_message_sender_id = v_me
   where id = p_conversation_id;

  -- 10. You have obviously read your own message.
  update public.conversation_members
     set last_read_seq = v_seq, last_delivered_seq = v_seq
   where conversation_id = p_conversation_id and user_id = v_me;

  return v_msg;
end;
$$;


-- ---------------------------------------------------------------------
-- create_upload_ticket
-- ---------------------------------------------------------------------
-- Step 1 of sharing a photo or document. Validates the file BEFORE any
-- bytes are accepted and hands back the object path the client should
-- upload to. The 5 MB / mime rules live in the constraints on
-- upload_tickets and message_attachments, so they hold even if a client
-- is patched to skip them.
create or replace function public.create_upload_ticket(
  p_conversation_id uuid,
  p_kind            public.attachment_kind,
  p_file_name       text,
  p_mime_type       text,
  p_size_bytes      integer
) returns public.upload_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me     uuid := auth.uid();
  v_ticket public.upload_tickets%rowtype;
  v_ext    text;
  v_path   text;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if not public.is_conversation_member(p_conversation_id, v_me) then
    raise exception 'You are not a member of this conversation' using errcode = '42501';
  end if;
  if p_size_bytes > 5242880 then
    raise exception 'Files must be 5 MB or smaller' using errcode = '22023';
  end if;
  if not public.check_rate_limit(v_me, 'upload', 20, interval '5 minutes') then
    raise exception 'Too many uploads. Try again shortly.' using errcode = '53400';
  end if;

  v_ext  := lower(coalesce(nullif(regexp_replace(p_file_name, '^.*\.', ''), p_file_name), 'bin'));
  -- Path is server-chosen so a client cannot overwrite another thread's
  -- object by supplying its own key.
  v_path := p_conversation_id::text || '/' || v_me::text || '/'
            || public.uuid_generate_v7()::text || '.' || v_ext;

  insert into public.upload_tickets (
    user_id, conversation_id, object_path, kind, file_name, mime_type, declared_size
  ) values (
    v_me, p_conversation_id, v_path, p_kind, p_file_name, p_mime_type, p_size_bytes
  )
  returning * into v_ticket;

  return v_ticket;
end;
$$;


-- ---------------------------------------------------------------------
-- mark_read
-- ---------------------------------------------------------------------
-- greatest() so an out-of-order ack from a slow device can never rewind
-- the read pointer and make already-read messages unread again.
create or replace function public.mark_read(p_conversation_id uuid, p_seq bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_read bigint;
  v_last bigint;
begin
  update public.conversation_members
     set last_read_seq      = greatest(last_read_seq, p_seq),
         last_delivered_seq = greatest(last_delivered_seq, p_seq)
   where conversation_id = p_conversation_id and user_id = v_me
  returning last_read_seq into v_read;

  if v_read is null then
    raise exception 'You are not a member of this conversation' using errcode = '42501';
  end if;

  select last_seq into v_last from public.conversations where id = p_conversation_id;

  -- Clear the message notifications this read just made irrelevant.
  update public.notifications
     set read_at = now()
   where user_id = v_me and kind = 'message'
     and target_id = p_conversation_id and read_at is null;

  return greatest(0, v_last - v_read);
end;
$$;


-- ---------------------------------------------------------------------
-- get_chat_list
-- ---------------------------------------------------------------------
-- One query for the whole Chats tab: DMs and group threads together,
-- with unread counts, the other person's details for DMs, and the last
-- message preview — no N+1 from the client.
create or replace function public.get_chat_list(p_limit int default 50, p_before timestamptz default null)
returns table (
  conversation_id  uuid,
  type             public.conversation_type,
  source_type      public.group_source,
  source_id        uuid,
  title            text,
  photo_url        text,
  member_count     integer,
  last_seq         bigint,
  last_message_at  timestamptz,
  last_message_preview text,
  last_message_sender_id uuid,
  unread_count     bigint,
  is_pinned        boolean,
  muted_until      timestamptz,
  other_user_id    uuid,
  other_user_name  text,
  other_user_avatar text,
  other_is_online  boolean,
  other_last_active timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.type,
    c.source_type,
    c.source_id,
    coalesce(c.title, op.full_name),
    coalesce(c.photo_url, op.avatar_url),
    c.member_count,
    c.last_seq,
    c.last_message_at,
    c.last_message_preview,
    c.last_message_sender_id,
    greatest(0, c.last_seq - m.last_read_seq) as unread_count,
    m.is_pinned,
    m.muted_until,
    op.id,
    op.full_name,
    op.avatar_url,
    -- Respect the "hide active status" privacy switch.
    case when op.hide_active_status then null else pr.is_online end,
    case when op.hide_active_status then null else pr.last_active end
  from public.conversation_members m
  join public.conversations c on c.id = m.conversation_id
  -- The other participant, DMs only.
  left join lateral (
    select p.*
    from public.conversation_members om
    join public.profiles p on p.id = om.user_id
    where om.conversation_id = c.id and om.user_id <> m.user_id
    limit 1
  ) op on c.type = 'direct'
  left join public.user_presence pr on pr.user_id = op.id
  where m.user_id = auth.uid()
    and m.left_at is null
    and c.archived_at is null
    and (p_before is null or c.last_message_at < p_before)
    -- A DM with nothing said yet should not clutter the list.
    and (c.last_seq > 0 or c.type = 'group')
  order by m.is_pinned desc, c.last_message_at desc nulls last
  limit least(p_limit, 100);
$$;


-- ---------------------------------------------------------------------
-- get_messages — keyset pagination
-- ---------------------------------------------------------------------
-- Cursor on `seq`, not OFFSET. OFFSET re-walks every skipped row, so
-- scrolling back through a long thread gets slower the further you go;
-- a seq cursor is a constant-cost index range scan every time.
create or replace function public.get_messages(
  p_conversation_id uuid,
  p_before_seq      bigint default null,
  p_limit           int default 40
)
returns table (
  id               uuid,
  seq              bigint,
  sender_id        uuid,
  sender_name      text,
  sender_avatar    text,
  kind             public.message_kind,
  body             text,
  reply_to_id      uuid,
  mentions         uuid[],
  attachment_count smallint,
  attachments      jsonb,
  edited_at        timestamptz,
  deleted_at       timestamptz,
  created_at       timestamptz,
  seen_by_all      boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select last_read_seq, visible_from_seq
    from public.conversation_members
    where conversation_id = p_conversation_id and user_id = auth.uid() and left_at is null
  ),
  -- Lowest read pointer among everyone else: a message at or below this
  -- has been seen by every member (the group "double blue tick").
  others as (
    select coalesce(min(last_read_seq), 0) as min_read
    from public.conversation_members
    where conversation_id = p_conversation_id and user_id <> auth.uid() and left_at is null
  )
  select
    msg.id,
    msg.seq,
    msg.sender_id,
    p.full_name,
    p.avatar_url,
    msg.kind,
    case when msg.deleted_at is null then msg.body else null end,
    msg.reply_to_id,
    msg.mentions,
    msg.attachment_count,
    case when msg.attachment_count = 0 or msg.deleted_at is not null then '[]'::jsonb else (
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'kind', a.kind, 'bucket', a.bucket, 'object_path', a.object_path,
        'file_name', a.file_name, 'mime_type', a.mime_type, 'size_bytes', a.size_bytes,
        'width', a.width, 'height', a.height, 'blurhash', a.blurhash,
        'thumb_path', a.thumb_path, 'page_count', a.page_count, 'scan_status', a.scan_status
      ) order by a.id)
      from public.message_attachments a
      where a.conversation_id = msg.conversation_id and a.message_id = msg.id
    ) end,
    msg.edited_at,
    msg.deleted_at,
    msg.created_at,
    msg.seq <= (select min_read from others)
  from public.messages msg
  cross join me
  left join public.profiles p on p.id = msg.sender_id
  where msg.conversation_id = p_conversation_id
    and exists (select 1 from me)
    and msg.seq > me.visible_from_seq
    and (p_before_seq is null or msg.seq < p_before_seq)
  order by msg.seq desc
  limit least(p_limit, 100);
$$;


-- ---------------------------------------------------------------------
-- total_unread — the tab-bar badge
-- ---------------------------------------------------------------------
create or replace function public.total_unread()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(greatest(0, c.last_seq - m.last_read_seq)), 0)
  from public.conversation_members m
  join public.conversations c on c.id = m.conversation_id
  where m.user_id = auth.uid()
    and m.left_at is null
    and (m.muted_until is null or m.muted_until < now());
$$;


-- ---------------------------------------------------------------------
-- delete_message — soft delete
-- ---------------------------------------------------------------------
-- The row survives so replies pointing at it do not dangle and so
-- moderators can still review reported content.
create or replace function public.delete_message(p_conversation_id uuid, p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_role public.member_role := public.conversation_role(p_conversation_id, v_me);
  v_sender uuid;
begin
  select sender_id into v_sender from public.messages
   where conversation_id = p_conversation_id and id = p_message_id;

  if v_sender is null then
    raise exception 'Message not found' using errcode = 'no_data_found';
  end if;
  if v_sender <> v_me and v_role not in ('owner', 'admin') then
    raise exception 'You can only delete your own messages' using errcode = '42501';
  end if;

  update public.messages
     set deleted_at = now(), deleted_by = v_me, body = null
   where conversation_id = p_conversation_id and id = p_message_id;
end;
$$;


-- ---------------------------------------------------------------------
-- join_group / leave_group
-- ---------------------------------------------------------------------
-- Because membership IS conversation_members, this one pair of functions
-- covers communities, clubs, study groups and project teams.
create or replace function public.join_group(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_conv public.conversations%rowtype;
  v_sg   public.study_groups%rowtype;
begin
  select * into v_conv from public.conversations where id = p_conversation_id;
  if not found or v_conv.type <> 'group' then
    raise exception 'Group not found' using errcode = 'no_data_found';
  end if;
  if (select university_id from public.profiles where id = v_me) <> v_conv.university_id then
    raise exception 'That group belongs to another campus' using errcode = '42501';
  end if;

  if v_conv.source_type = 'study_group' then
    select * into v_sg from public.study_groups where conversation_id = p_conversation_id;
    if v_conv.member_count >= v_sg.max_members then
      raise exception 'This study group is full' using errcode = '23514';
    end if;
  end if;

  insert into public.conversation_members (conversation_id, user_id, visible_from_seq)
  -- New joiners start at the current head: no 50k-message backlog on a
  -- busy club thread, and no history they were never part of.
  values (p_conversation_id, v_me, v_conv.last_seq)
  on conflict (conversation_id, user_id)
    do update set left_at = null, visible_from_seq = excluded.visible_from_seq
    where conversation_members.left_at is not null;
end;
$$;


-- ---------------------------------------------------------------------
-- create_study_group
-- ---------------------------------------------------------------------
-- A study group and its conversation have to be born together — the
-- conversation_id column is NOT NULL, and a half-created pair would be
-- a group nobody can talk in. The client cannot INSERT into
-- `conversations` (no policy grants it), so this is the only way in.
create or replace function public.create_study_group(
  p_subject     text,
  p_title       text,
  p_description text default '',
  p_schedule    text default null,
  p_venue       text default null,
  p_max_members smallint default 8
) returns public.study_groups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_uni  uuid;
  v_conv uuid;
  v_sg   public.study_groups%rowtype;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if not public.check_rate_limit(v_me, 'create_group', 5, interval '1 day') then
    raise exception 'You have created too many study groups today' using errcode = '53400';
  end if;

  select university_id into v_uni from public.profiles
   where id = v_me and deleted_at is null;
  if v_uni is null then
    raise exception 'Profile not found' using errcode = 'no_data_found';
  end if;

  insert into public.conversations (
    university_id, type, source_type, source_id, title, description, created_by
  ) values (
    v_uni, 'group', 'study_group', public.uuid_generate_v7(), p_title, p_description, v_me
  )
  returning id, source_id into v_conv, v_sg.id;

  insert into public.study_groups (
    id, university_id, conversation_id, subject, title, description,
    schedule, venue, host_id, max_members
  ) values (
    v_sg.id, v_uni, v_conv, p_subject, p_title, coalesce(p_description, ''),
    p_schedule, p_venue, v_me, p_max_members
  )
  returning * into v_sg;

  -- The host is the first member, and owns the thread.
  insert into public.conversation_members (conversation_id, user_id, role)
  values (v_conv, v_me, 'owner');

  return v_sg;
end;
$$;


create or replace function public.leave_group(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversation_members
     set left_at = now()
   where conversation_id = p_conversation_id and user_id = auth.uid() and left_at is null;
end;
$$;


-- ---------------------------------------------------------------------
-- request_account_deletion
-- ---------------------------------------------------------------------
-- A client can never delete its own auth.users row, and `deleted_at` is
-- not in the column grants on `profiles` — otherwise a compromised
-- session could erase the account outright. This marks the profile and
-- lets purge_deleted_profiles() do the real erasure after 30 days, which
-- also gives the student a window to change their mind.
create or replace function public.request_account_deletion()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  update public.profiles
     set deleted_at = coalesce(deleted_at, now()),
         deactivated_at = coalesce(deactivated_at, now()),
         discoverable = false
   where id = v_me;

  -- Drop out of every thread immediately rather than waiting for the
  -- purge: a deleted account should stop appearing in other people's
  -- chat lists straight away.
  update public.conversation_members
     set left_at = now()
   where user_id = v_me and left_at is null;
end;
$$;


-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
-- SECURITY DEFINER functions must not be callable by anon.
revoke all on function public.send_message(uuid, text, public.message_kind, uuid, uuid, jsonb, uuid[]) from public, anon;
revoke all on function public.create_upload_ticket(uuid, public.attachment_kind, text, text, integer) from public, anon;
revoke all on function public.get_or_create_direct_conversation(uuid) from public, anon;
revoke all on function public.mark_read(uuid, bigint) from public, anon;
revoke all on function public.delete_message(uuid, uuid) from public, anon;
revoke all on function public.join_group(uuid) from public, anon;
revoke all on function public.leave_group(uuid) from public, anon;
revoke all on function public.create_study_group(text, text, text, text, text, smallint) from public, anon;

grant execute on function public.send_message(uuid, text, public.message_kind, uuid, uuid, jsonb, uuid[]) to authenticated;
grant execute on function public.create_upload_ticket(uuid, public.attachment_kind, text, text, integer) to authenticated;
grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;
grant execute on function public.mark_read(uuid, bigint) to authenticated;
grant execute on function public.get_chat_list(int, timestamptz) to authenticated;
grant execute on function public.get_messages(uuid, bigint, int) to authenticated;
grant execute on function public.total_unread() to authenticated;
grant execute on function public.delete_message(uuid, uuid) to authenticated;
grant execute on function public.join_group(uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.create_study_group(text, text, text, text, text, smallint) to authenticated;

revoke all on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;
