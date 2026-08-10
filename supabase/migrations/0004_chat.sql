-- =====================================================================
-- 0004  Chat: conversations, members, messages, attachments
-- =====================================================================
-- This is the part of the schema that has to survive the most growth, so
-- the three decisions that shape it are spelled out up front.
--
-- 1. ONE conversation model for DMs and groups.
--    A `direct` conversation is just a group with exactly two members and
--    a uniqueness key. Two parallel table sets would mean two of every
--    query, index, RLS policy and realtime subscription for no benefit.
--
-- 2. A per-conversation `seq` counter, not timestamps, for ordering.
--    Timestamps collide, clocks drift, and "unread since" becomes a
--    scan. A gapless-enough bigint per conversation makes pagination a
--    range scan on the primary key, and makes unread count pure
--    arithmetic: conversations.last_seq - conversation_members.last_read_seq.
--    No counter table, no per-message receipt rows, no drift.
--
-- 3. `messages` is HASH partitioned by conversation_id, not by time.
--    Every read in a chat app is "the last N messages of conversation X".
--    Hash partitioning on conversation_id prunes that to exactly one
--    partition. Time partitioning — the usual reflex — would force every
--    such query to probe the index of every partition, because the
--    pagination key (seq) tells the planner nothing about created_at.
--    Retention is the one thing time partitioning wins at, and that runs
--    as a background job where the extra cost does not matter.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------
create table if not exists public.conversations (
  id            uuid primary key default public.uuid_generate_v7(),
  university_id uuid not null references public.universities(id),
  type          public.conversation_type not null,

  -- For group threads: the campus entity this thread belongs to, so that
  -- joining a club and appearing in its chat are the same action.
  -- (chat_model.dart: "Its id is the id of that community/club/group, so
  -- joining and leaving stay in sync.")
  source_type   public.group_source,
  source_id     uuid,

  title       text,
  photo_url   text,
  description text,
  created_by  uuid references public.profiles(id) on delete set null,

  -- Chat-list denormalisation. Without these the list screen would need
  -- a lateral "last message" subquery per row on every open.
  last_seq              bigint not null default 0,
  last_message_at       timestamptz,
  last_message_preview  text,
  last_message_sender_id uuid references public.profiles(id) on delete set null,
  member_count          integer not null default 0,

  -- Moderation / lifecycle
  is_locked   boolean not null default false,  -- read-only (admins only)
  archived_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- Canonical key for a 1:1 thread: sorted pair of user ids. NULL for
  -- groups. This is what stops two devices racing to create two DMs
  -- between the same two people.
  direct_key text,

  constraint conversations_direct_shape check (
    (type = 'direct' and direct_key is not null and source_type is null)
    or
    (type = 'group'  and direct_key is null and source_type is not null)
  )
);

create unique index if not exists conversations_direct_key_uniq
  on public.conversations (direct_key) where direct_key is not null;

-- A club/community/study group has exactly one thread.
create unique index if not exists conversations_source_uniq
  on public.conversations (source_type, source_id)
  where source_id is not null;

create index if not exists conversations_recent_idx
  on public.conversations (last_message_at desc nulls last)
  where archived_at is null;

create or replace trigger set_updated_at before update on public.conversations
  for each row execute function public.tg_set_updated_at();


-- ---------------------------------------------------------------------
-- Membership + per-user read state
-- ---------------------------------------------------------------------
-- This table is also the membership record for clubs, communities and
-- study groups (see 0005). One join table instead of four.
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  role            public.member_role not null default 'member',

  -- Read state. `last_read_seq` is the whole unread system: the badge is
  -- conversations.last_seq - last_read_seq, computed at read time, and a
  -- DM's blue tick is "the other member's last_read_seq >= my seq".
  last_read_seq      bigint not null default 0,
  last_delivered_seq bigint not null default 0,

  -- Per-user chat list state
  is_pinned    boolean not null default false,
  muted_until  timestamptz,
  notify_level public.notification_level not null default 'all',
  -- Hides history from before this seq (used when someone joins a big
  -- club thread — they should not get 50k backlogged messages).
  visible_from_seq bigint not null default 0,

  joined_at timestamptz not null default now(),
  left_at   timestamptz,

  primary key (conversation_id, user_id)
) with (fillfactor = 80);   -- last_read_seq updates constantly; leave HOT room

-- "My chat list". Partial so left conversations cost nothing.
create index if not exists conversation_members_user_idx
  on public.conversation_members (user_id, is_pinned desc, conversation_id)
  where left_at is null;

-- Fan-out: "who do I push this message to". Covering index — the chat
-- server reads user_id + mute state without touching the heap.
create index if not exists conversation_members_fanout_idx
  on public.conversation_members (conversation_id)
  include (user_id, notify_level, muted_until)
  where left_at is null;


-- Keep conversations.member_count honest.
create or replace function public.tg_conversation_member_count()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and new.left_at is null then
    update public.conversations set member_count = member_count + 1 where id = new.conversation_id;
  elsif tg_op = 'DELETE' and old.left_at is null then
    update public.conversations set member_count = member_count - 1 where id = old.conversation_id;
  elsif tg_op = 'UPDATE' and (old.left_at is null) is distinct from (new.left_at is null) then
    update public.conversations
       set member_count = member_count + case when new.left_at is null then 1 else -1 end
     where id = new.conversation_id;
  end if;
  return null;
end;
$$;

create or replace trigger conversation_member_count
  after insert or delete or update of left_at on public.conversation_members
  for each row execute function public.tg_conversation_member_count();


-- ---------------------------------------------------------------------
-- Messages  (hash partitioned by conversation_id)
-- ---------------------------------------------------------------------
-- Partition-key rules force the PK to include conversation_id — which is
-- exactly what we want anyway: (conversation_id, seq) is both the
-- identity and the pagination order, so history reads are a single
-- backwards index range scan inside one partition.
create table if not exists public.messages (
  conversation_id uuid   not null,
  seq             bigint not null,
  id              uuid   not null default public.uuid_generate_v7(),

  -- NULL for `system` messages ("Riya joined the group").
  sender_id uuid references public.profiles(id) on delete set null,
  kind      public.message_kind not null default 'text',
  body      text check (length(body) <= 4000),

  -- Replies never cross conversations, so the FK carries the partition
  -- key and stays inside one partition.
  reply_to_id uuid,

  -- Idempotency. The client generates this before the first send attempt
  -- and reuses it on every retry, so a flaky campus wifi connection can
  -- never produce duplicate bubbles. NOT NULL with a default because
  -- partitioned tables do not support partial unique indexes.
  client_msg_id uuid not null default gen_random_uuid(),

  attachment_count smallint not null default 0,
  -- Mentioned user ids, for the `mentions` notification level.
  mentions   uuid[] not null default '{}',

  edited_at  timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),

  primary key (conversation_id, seq)
) partition by hash (conversation_id);

-- 16 partitions: enough that no single partition's index dominates
-- memory at ~10^8 rows, few enough that planning stays cheap. Changing
-- this later means a rewrite, so it is set generously from day one.
do $$
declare i int;
begin
  for i in 0..15 loop
    execute format(
      'create table if not exists public.messages_p%s partition of public.messages
         for values with (modulus 16, remainder %s)', i, i);
  end loop;
end $$;

-- Lookup by message id (deep links, notification taps, moderation) and
-- the target for the reply / attachment foreign keys.
create unique index if not exists messages_conv_id_uniq
  on public.messages (conversation_id, id);

-- Idempotent send.
create unique index if not exists messages_client_id_uniq
  on public.messages (conversation_id, client_msg_id);

-- "Everything this user ever sent" — account deletion and moderation.
create index if not exists messages_sender_idx
  on public.messages (sender_id, created_at desc);

-- BRIN, not B-tree: created_at is naturally correlated with physical
-- order (v7 ids + append-only writes), so a few KB of BRIN does the job
-- of a multi-GB B-tree for the retention job's range deletes.
create index if not exists messages_created_brin
  on public.messages using brin (created_at) with (pages_per_range = 64);

-- Added via ALTER because the target unique index has to exist first.
do $$ begin
  alter table public.messages
    add constraint messages_reply_fk
    foreign key (conversation_id, reply_to_id)
    references public.messages (conversation_id, id) on delete set null;
exception when duplicate_object then null; end $$;

-- A text/system message must have a body; an attachment message need not.
-- Deleted messages are exempt: delete_message() and the account-purge job
-- both null the body out, and without this exemption a soft delete of a
-- text message would fail the constraint.
do $$ begin
  alter table public.messages
    add constraint messages_body_present check (
      deleted_at is not null
      or kind in ('photo', 'document')
      or coalesce(length(trim(body)), 0) > 0
    );
exception when duplicate_object then null; end $$;


-- ---------------------------------------------------------------------
-- Attachments  (photos and documents)
-- ---------------------------------------------------------------------
-- A separate table rather than a jsonb column: these rows are queried on
-- their own for the "Media & Documents" tab of a chat, they carry a scan
-- lifecycle, and storage cleanup needs to join on them.
--
-- Partitioned the same way as messages so the FK is local to a partition
-- and the media tab prunes to one partition too.
create table if not exists public.message_attachments (
  conversation_id uuid not null,
  id              uuid not null default public.uuid_generate_v7(),
  message_id      uuid not null,

  kind        public.attachment_kind not null,
  -- Where the bytes live in Supabase Storage.
  bucket      text not null default 'chat-media',
  object_path text not null,
  file_name   text not null check (length(file_name) <= 255),
  mime_type   text not null,

  -- 5 MB, matching AttachmentService.maxBytes. Enforced here as well as
  -- in the app and the storage policy — the app limit is a courtesy, the
  -- database limit is the one that actually holds.
  size_bytes  integer not null check (size_bytes > 0 and size_bytes <= 5242880),

  -- Photos only
  width      integer,
  height     integer,
  blurhash   text,          -- placeholder while the full image loads
  thumb_path text,          -- generated 400px preview

  -- Documents only
  page_count integer,

  checksum_sha256 bytea,    -- dedup + integrity
  scan_status public.scan_status not null default 'pending',
  scanned_at  timestamptz,
  created_at  timestamptz not null default now(),

  primary key (conversation_id, id),

  foreign key (conversation_id, message_id)
    references public.messages (conversation_id, id) on delete cascade,

  -- Mime allow-list mirrors AttachmentService's extension lists.
  constraint attachments_mime_allowed check (
    (kind = 'photo' and mime_type in (
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'))
    or
    (kind = 'document' and mime_type in (
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'text/plain'))
  )
) partition by hash (conversation_id);

do $$
declare i int;
begin
  for i in 0..15 loop
    execute format(
      'create table if not exists public.message_attachments_p%s
         partition of public.message_attachments
         for values with (modulus 16, remainder %s)', i, i);
  end loop;
end $$;

create index if not exists attachments_message_idx
  on public.message_attachments (conversation_id, message_id);

-- The "Media & Documents" tab.
create index if not exists attachments_gallery_idx
  on public.message_attachments (conversation_id, kind, created_at desc);

-- Work queue for the virus/content scanner.
create index if not exists attachments_scan_queue_idx
  on public.message_attachments (created_at)
  where scan_status = 'pending';

-- Stops the same storage object being attached twice. The partition key
-- has to be in here — a unique index on a partitioned table must contain
-- every partitioning column, because Postgres enforces uniqueness per
-- partition and cannot see across them.
--
-- That makes this a per-conversation guarantee rather than a global one,
-- which is enough: object paths are server-generated in
-- create_upload_ticket() and `upload_tickets.object_path` is globally
-- UNIQUE, so a path cannot exist in two conversations to begin with.
create unique index if not exists attachments_object_uniq
  on public.message_attachments (conversation_id, bucket, object_path);


-- ---------------------------------------------------------------------
-- Upload tickets
-- ---------------------------------------------------------------------
-- The upload happens BEFORE the message exists: the client asks for a
-- signed upload URL, PUTs the file, then sends the message referencing
-- the path. That leaves a window where bytes exist with nothing pointing
-- at them — a user who backs out of the picker, or a send that fails.
--
-- A ticket records the intent so (a) the size/mime is validated before a
-- single byte is accepted, and (b) the nightly job knows which objects
-- are orphans and can safely delete them.
create table if not exists public.upload_tickets (
  id              uuid primary key default public.uuid_generate_v7(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  bucket          text not null default 'chat-media',
  object_path     text not null unique,
  kind            public.attachment_kind not null,
  file_name       text not null,
  mime_type       text not null,
  declared_size   integer not null check (declared_size > 0 and declared_size <= 5242880),
  consumed_at     timestamptz,   -- set when a message_attachments row is created
  expires_at      timestamptz not null default now() + interval '1 hour',
  created_at      timestamptz not null default now()
);

create index if not exists upload_tickets_orphans_idx
  on public.upload_tickets (expires_at)
  where consumed_at is null;


-- ---------------------------------------------------------------------
-- Reactions
-- ---------------------------------------------------------------------
create table if not exists public.message_reactions (
  conversation_id uuid not null,
  message_id      uuid not null,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  emoji           text not null check (length(emoji) <= 16),
  created_at      timestamptz not null default now(),
  primary key (conversation_id, message_id, user_id, emoji),
  foreign key (conversation_id, message_id)
    references public.messages (conversation_id, id) on delete cascade
) partition by hash (conversation_id);

do $$
declare i int;
begin
  for i in 0..7 loop
    execute format(
      'create table if not exists public.message_reactions_p%s
         partition of public.message_reactions
         for values with (modulus 8, remainder %s)', i, i);
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- What is NOT in this schema, on purpose
-- ---------------------------------------------------------------------
-- * Typing indicators. Valid for ~3 seconds. Writing them to Postgres
--   would generate more write traffic than the messages themselves.
--   Keep them in the chat server's memory / Redis pub-sub.
--
-- * Per-message read receipts (one row per user per message). In a
--   200-member club thread that is 200 rows per message. `last_read_seq`
--   answers the same question in one integer comparison. If per-message
--   "seen by" is ever needed for groups, derive it: a member has seen
--   message N iff their last_read_seq >= N.
--
-- * Online status. Lives in user_presence / Redis, see 0002.
