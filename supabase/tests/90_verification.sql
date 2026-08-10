-- =====================================================================
-- Campus Connect — verification suite
--
-- Covers the five checks named in DATABASE.md plus the RLS, constraint
-- and trigger behaviour those five depend on.
--
-- Users are impersonated exactly as PostgREST does it:
--   set local role authenticated;
--   set local request.jwt.claim.sub = '<uuid>';
-- =====================================================================

\set ON_ERROR_STOP on
set client_min_messages = warning;

create schema if not exists t;

drop table if exists t.results;
create table t.results (
  id     serial primary key,
  name   text,
  passed boolean,
  detail text
);

create or replace function t.ok(p_name text, p_cond boolean, p_detail text default '')
returns void language plpgsql as $$
begin
  insert into t.results (name, passed, detail) values (p_name, p_cond, p_detail);
end $$;

create or replace function t.eq(p_name text, p_got anyelement, p_want anyelement)
returns void language plpgsql as $$
begin
  insert into t.results (name, passed, detail)
  values (p_name, p_got is not distinct from p_want,
          format('got=%s want=%s', coalesce(p_got::text,'<null>'), coalesce(p_want::text,'<null>')));
end $$;

-- Register a new student the way Supabase Auth would.
create or replace function t.signup(p_email text, p_name text)
returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, p_email, jsonb_build_object('full_name', p_name));
  return v_id;
end $$;

create or replace function t.become(p_user uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- The suite runs partly as `authenticated`, so the harness itself has to
-- be reachable from that role. SECURITY DEFINER on signup() because it
-- writes to auth.users, which authenticated must never be able to do.
alter function t.signup(text, text) security definer;

drop table if exists t.fixtures;
create table t.fixtures (label text primary key, id uuid);
drop table if exists t.conv;
create table t.conv (id uuid);

grant usage on schema t to public;
grant all on all tables in schema t to public;
grant execute on all functions in schema t to public;
grant all on all sequences in schema t to public;
alter function t.ok(text, boolean, text) security definer;
alter function t.eq(text, anyelement, anyelement) security definer;


-- =====================================================================
-- Fixtures
-- =====================================================================
do $$
begin
  insert into t.fixtures values
    ('a', t.signup('21bcs5084@cuchd.in', 'Aarav Sharma')),   -- CSE, 2021
    ('b', t.signup('21bcs7777@cuchd.in', 'Bhavya Singh')),   -- CSE, 2021
    ('c', t.signup('22bme1234@cuchd.in', 'Chirag Verma')),   -- Mechanical, 2022
    ('d', t.signup('23bba0001@cuchd.in', 'Diya Kapoor'));    -- Management, 2023
end $$;


-- =====================================================================
-- 1. Signup trigger: profile shell + university id parsing
-- =====================================================================
do $$
declare p public.profiles%rowtype; v_a uuid;
begin
  select id into v_a from t.fixtures where label = 'a';
  select * into p from public.profiles where id = v_a;

  perform t.ok('signup creates profile', p.id is not null);
  perform t.eq('uid parsed',            p.university_uid::text, '21bcs5084');
  perform t.eq('admission year parsed', p.admission_year::int, 2021);
  perform t.eq('department from program', p.department, 'Computer Science');
  perform t.eq('course from program',     p.course, 'B.E. CSE');
  perform t.eq('username defaults to uid', p.username::text, '21bcs5084');
  perform t.eq('email verified on signup', p.verification_level::text, 'email');
  perform t.eq('full_name from metadata', p.full_name, 'Aarav Sharma');

  -- Mechanical student must land in a different department.
  select * into p from public.profiles where id = (select id from t.fixtures where label='c');
  perform t.eq('second program maps too', p.department, 'Mechanical');
  perform t.eq('2022 batch', p.admission_year::int, 2022);
end $$;

-- Non-CU domains must be refused at the trigger.
do $$
begin
  begin
    perform t.signup('someone@gmail.com', 'Outsider');
    perform t.ok('non-CU email rejected', false, 'insert succeeded');
  exception when others then
    perform t.ok('non-CU email rejected', true, sqlerrm);
  end;

  begin
    perform t.signup('notanid@cuchd.in', 'Bad Id');
    perform t.ok('malformed university id rejected', false, 'insert succeeded');
  exception when others then
    perform t.ok('malformed university id rejected', true, sqlerrm);
  end;
end $$;


-- =====================================================================
-- 2. Department community auto-join
-- =====================================================================
do $$
declare v_n int; v_conv uuid;
begin
  select c.conversation_id into v_conv
  from public.communities c where c.name = 'Computer Science' and c.is_auto_join;

  perform t.ok('CSE community seeded', v_conv is not null);

  select count(*) into v_n
  from public.conversation_members m
  where m.conversation_id = v_conv
    and m.user_id in (select id from t.fixtures where label in ('a','b'));

  perform t.eq('both CSE students auto-joined', v_n, 2);

  select count(*) into v_n
  from public.conversation_members m
  where m.conversation_id = v_conv
    and m.user_id = (select id from t.fixtures where label = 'c');
  perform t.eq('mechanical student not in CSE community', v_n, 0);

  select member_count into v_n from public.conversations where id = v_conv;
  perform t.eq('member_count trigger tracked auto-joins', v_n, 2);
end $$;


-- =====================================================================
-- 3. Connections: state machine
-- =====================================================================
do $$
declare v_a uuid; v_b uuid; v_conn uuid;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';

  set local role authenticated;
  perform t.become(v_a);

  insert into public.connections (requester_id, addressee_id, purpose)
  values (v_a, v_b, 'Study partner') returning id into v_conn;
  perform t.ok('A can send a connection request', v_conn is not null);

  -- The requester must not be able to accept their own request.
  begin
    update public.connections set state = 'accepted' where id = v_conn;
    perform t.ok('requester cannot self-accept', false, 'update succeeded');
  exception when others then
    perform t.ok('requester cannot self-accept', true, sqlerrm);
  end;

  -- Duplicate live request for the same pair is blocked by the index.
  begin
    insert into public.connections (requester_id, addressee_id) values (v_a, v_b);
    perform t.ok('duplicate pending request blocked', false, 'insert succeeded');
  exception when others then
    perform t.ok('duplicate pending request blocked', true, 'unique index held');
  end;

  -- B accepts.
  perform t.become(v_b);
  update public.connections set state = 'accepted' where id = v_conn;
  perform t.ok('addressee can accept', (select state from public.connections where id = v_conn) = 'accepted');
  perform t.ok('responded_at stamped', (select responded_at from public.connections where id = v_conn) is not null);

  reset role;
  perform t.ok('are_connected sees it', public.are_connected(v_a, v_b));
  perform t.ok('are_connected is symmetric', public.are_connected(v_b, v_a));
  perform t.ok('unrelated pair not connected',
    not public.are_connected(v_a, (select id from t.fixtures where label='c')));
end $$;


-- =====================================================================
-- 4. DM creation gate
-- =====================================================================
do $$
declare v_a uuid; v_b uuid; v_c uuid; v_conv uuid; v_conv2 uuid;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_c from t.fixtures where label='c';

  set local role authenticated;
  perform t.become(v_a);

  -- Not connected to C, and C does not accept open DMs.
  begin
    perform public.get_or_create_direct_conversation(v_c);
    perform t.ok('DM blocked without connection', false, 'succeeded');
  exception when others then
    perform t.ok('DM blocked without connection', true, sqlerrm);
  end;

  v_conv := public.get_or_create_direct_conversation(v_b);
  perform t.ok('DM opens with a connection', v_conv is not null);

  -- Double-tap must not create a second thread.
  v_conv2 := public.get_or_create_direct_conversation(v_b);
  perform t.eq('DM creation is idempotent', v_conv2, v_conv);

  perform t.eq('DM has exactly 2 members',
    (select count(*)::int from public.conversation_members where conversation_id = v_conv), 2);

  -- Self-DM is nonsense.
  begin
    perform public.get_or_create_direct_conversation(v_a);
    perform t.ok('self-DM rejected', false, 'succeeded');
  exception when others then
    perform t.ok('self-DM rejected', true, sqlerrm);
  end;

  reset role;
  insert into t.conv values (v_conv);
end $$;


-- =====================================================================
-- 5. send_message + idempotency  (DATABASE.md tests 1 and 2)
-- =====================================================================
do $$
declare
  v_a uuid; v_b uuid; v_conv uuid;
  v_client uuid := gen_random_uuid();
  m1 public.messages%rowtype;
  m2 public.messages%rowtype;
  v_n int;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_conv from t.conv;

  set local role authenticated;
  perform t.become(v_a);

  m1 := public.send_message(v_conv, 'Notes bhej dena DBMS ke', 'text', v_client);
  perform t.ok('message sent', m1.id is not null);
  perform t.eq('first message gets seq 1', m1.seq, 1::bigint);
  perform t.eq('sender recorded', m1.sender_id, v_a);

  -- Same client_msg_id: a retry, not a new message.
  m2 := public.send_message(v_conv, 'Notes bhej dena DBMS ke', 'text', v_client);
  perform t.eq('retry returns the original message', m2.id, m1.id);
  perform t.eq('retry does not advance seq', m2.seq, 1::bigint);

  select count(*)::int into v_n from public.messages where conversation_id = v_conv;
  perform t.eq('retry produced exactly one row', v_n, 1);

  select last_seq into v_n from public.conversations where id = v_conv;
  perform t.eq('conversation last_seq is 1', v_n, 1);

  perform t.eq('chat list preview updated',
    (select last_message_preview from public.conversations where id = v_conv),
    'Notes bhej dena DBMS ke');

  -- A different client id is a genuinely new message.
  m2 := public.send_message(v_conv, 'aur OS ke bhi', 'text', gen_random_uuid());
  perform t.eq('new client id advances seq', m2.seq, 2::bigint);

  -- Empty text is not a message.
  begin
    perform public.send_message(v_conv, '   ', 'text', gen_random_uuid());
    perform t.ok('empty text rejected', false, 'succeeded');
  exception when others then
    perform t.ok('empty text rejected', true, sqlerrm);
  end;

  reset role;
end $$;


-- =====================================================================
-- 6. Unread arithmetic  (DATABASE.md test 5)
-- =====================================================================
do $$
declare v_a uuid; v_b uuid; v_conv uuid; v_unread bigint;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_conv from t.conv;

  set local role authenticated;

  -- Sender has read their own messages.
  perform t.become(v_a);
  perform t.eq('sender unread is 0',
    (select greatest(0, c.last_seq - m.last_read_seq)
     from public.conversations c
     join public.conversation_members m on m.conversation_id = c.id and m.user_id = v_a
     where c.id = v_conv), 0::bigint);

  -- Recipient has two waiting.
  perform t.become(v_b);
  perform t.eq('recipient unread is 2',
    (select greatest(0, c.last_seq - m.last_read_seq)
     from public.conversations c
     join public.conversation_members m on m.conversation_id = c.id and m.user_id = v_b
     where c.id = v_conv), 2::bigint);

  perform t.ok('total_unread counts it', public.total_unread() >= 2);

  -- Read up to seq 1: one left.
  v_unread := public.mark_read(v_conv, 1);
  perform t.eq('mark_read returns remaining', v_unread, 1::bigint);

  v_unread := public.mark_read(v_conv, 2);
  perform t.eq('fully read', v_unread, 0::bigint);

  -- An out-of-order ack from a slow device must not rewind the pointer.
  v_unread := public.mark_read(v_conv, 1);
  perform t.eq('mark_read never rewinds', v_unread, 0::bigint);
  perform t.eq('read pointer held at 2',
    (select last_read_seq from public.conversation_members
      where conversation_id = v_conv and user_id = v_b), 2::bigint);

  reset role;
end $$;


-- =====================================================================
-- 7. Attachments  (DATABASE.md test 3: the 5 MB limit)
-- =====================================================================
do $$
declare
  v_a uuid; v_conv uuid;
  v_ticket public.upload_tickets%rowtype;
  v_msg public.messages%rowtype;
  v_att public.message_attachments%rowtype;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_conv from t.conv;

  set local role authenticated;
  perform t.become(v_a);

  -- 6 MB must be refused before a single byte is accepted.
  begin
    perform public.create_upload_ticket(v_conv, 'photo', 'Farewell group photo.jpg', 'image/jpeg', 6 * 1024 * 1024);
    perform t.ok('6 MB upload rejected', false, 'ticket issued');
  exception when others then
    perform t.ok('6 MB upload rejected', true, sqlerrm);
  end;

  -- 2.1 MB PDF is fine.
  v_ticket := public.create_upload_ticket(v_conv, 'document', 'DBMS Unit-3 Notes.pdf', 'application/pdf', 2202009);
  perform t.ok('valid document ticket issued', v_ticket.id is not null);
  perform t.ok('object path is server-generated and scoped to the conversation',
    v_ticket.object_path like v_conv::text || '/' || v_a::text || '/%');
  perform t.ok('path keeps the extension', v_ticket.object_path like '%.pdf');

  -- Sending with a made-up path must fail: no ticket backs it.
  begin
    perform public.send_message(v_conv, null, 'document', gen_random_uuid(), null,
      jsonb_build_array(jsonb_build_object('object_path', 'someone-elses/file.pdf')));
    perform t.ok('unticketed attachment rejected', false, 'succeeded');
  exception when others then
    perform t.ok('unticketed attachment rejected', true, sqlerrm);
  end;

  -- The real send.
  v_msg := public.send_message(v_conv, null, 'document', gen_random_uuid(), null,
    jsonb_build_array(jsonb_build_object('object_path', v_ticket.object_path, 'page_count', 12)));

  perform t.eq('document message stored', v_msg.kind::text, 'document');
  perform t.eq('attachment counted', v_msg.attachment_count::int, 1);

  select * into v_att from public.message_attachments
   where conversation_id = v_conv and message_id = v_msg.id;

  perform t.ok('attachment row created', v_att.id is not null);
  perform t.eq('filename came from the ticket, not the payload', v_att.file_name, 'DBMS Unit-3 Notes.pdf');
  perform t.eq('size came from the ticket', v_att.size_bytes, 2202009);
  perform t.eq('mime came from the ticket', v_att.mime_type, 'application/pdf');
  perform t.eq('page_count came from the payload', v_att.page_count, 12);
  perform t.eq('scan starts pending', v_att.scan_status::text, 'pending');
  perform t.eq('preview shows the filename',
    (select last_message_preview from public.conversations where id = v_conv),
    '📄 DBMS Unit-3 Notes.pdf');

  -- The ticket is now spent and cannot be replayed.
  perform t.ok('ticket consumed',
    (select consumed_at from public.upload_tickets where id = v_ticket.id) is not null);

  begin
    perform public.send_message(v_conv, null, 'document', gen_random_uuid(), null,
      jsonb_build_array(jsonb_build_object('object_path', v_ticket.object_path)));
    perform t.ok('consumed ticket cannot be reused', false, 'succeeded');
  exception when others then
    perform t.ok('consumed ticket cannot be reused', true, sqlerrm);
  end;

  -- A photo message, to check the other preview branch.
  v_ticket := public.create_upload_ticket(v_conv, 'photo', 'Lecture whiteboard.jpg', 'image/jpeg', 2516582);
  v_msg := public.send_message(v_conv, null, 'photo', gen_random_uuid(), null,
    jsonb_build_array(jsonb_build_object('object_path', v_ticket.object_path,
                                         'width', 1600, 'height', 1200, 'blurhash', 'LKO2')));
  perform t.eq('photo preview', (select last_message_preview from public.conversations where id = v_conv), '📷 Photo');
  perform t.eq('photo dimensions kept',
    (select width from public.message_attachments where conversation_id = v_conv and message_id = v_msg.id), 1600);

  reset role;
end $$;

-- The DB-level size cap holds even if the ticket path is bypassed.
do $$
declare v_conv uuid; v_msg_id uuid;
begin
  select id into v_conv from t.conv;
  select id into v_msg_id from public.messages where conversation_id = v_conv and seq = 1;

  begin
    insert into public.message_attachments (
      conversation_id, message_id, kind, object_path, file_name, mime_type, size_bytes)
    values (v_conv, v_msg_id, 'photo', 'x/y/z.jpg', 'huge.jpg', 'image/jpeg', 9999999);
    perform t.ok('oversize attachment blocked by constraint', false, 'insert succeeded');
  exception when others then
    perform t.ok('oversize attachment blocked by constraint', true, 'check constraint held');
  end;

  begin
    insert into public.message_attachments (
      conversation_id, message_id, kind, object_path, file_name, mime_type, size_bytes)
    values (v_conv, v_msg_id, 'document', 'x/y/z.exe', 'virus.exe', 'application/x-msdownload', 1000);
    perform t.ok('disallowed mime blocked by constraint', false, 'insert succeeded');
  exception when others then
    perform t.ok('disallowed mime blocked by constraint', true, 'mime allow-list held');
  end;
end $$;


-- =====================================================================
-- 8. Blocking  (DATABASE.md test 4)
-- =====================================================================
do $$
declare v_a uuid; v_b uuid; v_conv uuid;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_conv from t.conv;

  set local role authenticated;
  perform t.become(v_b);

  insert into public.blocks (blocker_id, blocked_id) values (v_b, v_a);
  perform t.ok('block recorded', public.is_blocked_either_way(v_a, v_b));

  -- Blocking must sever the connection, not leave it dangling.
  reset role;
  perform t.ok('block severed the connection', not public.are_connected(v_a, v_b));

  -- The thread is read-only for the blocked sender, immediately.
  set local role authenticated;
  perform t.become(v_a);
  begin
    perform public.send_message(v_conv, 'hello?', 'text', gen_random_uuid());
    perform t.ok('blocked sender cannot send', false, 'message went through');
  exception when others then
    perform t.ok('blocked sender cannot send', true, sqlerrm);
  end;

  -- And in the other direction too.
  perform t.become(v_b);
  begin
    perform public.send_message(v_conv, 'go away', 'text', gen_random_uuid());
    perform t.ok('blocker cannot send either', false, 'message went through');
  exception when others then
    perform t.ok('blocker cannot send either', true, sqlerrm);
  end;

  -- A blocked student disappears from the other's view.
  perform t.become(v_a);
  perform t.eq('blocked user hidden from profile reads',
    (select count(*)::int from public.profiles where id = v_b), 0);

  reset role;
  delete from public.blocks where blocker_id = v_b and blocked_id = v_a;

  -- Unblocking does NOT restore the connection: the block cancelled it,
  -- so they have to reconnect. Assert that, then reconnect so the
  -- remaining tests have a live DM to work with.
  perform t.ok('unblocking does not silently restore the connection',
    not public.are_connected(v_a, v_b));

  insert into public.connections (requester_id, addressee_id, state, responded_at)
  values (v_a, v_b, 'accepted', now());
  perform t.ok('they can reconnect after an unblock', public.are_connected(v_a, v_b));
end $$;


-- =====================================================================
-- 9. RLS isolation
-- =====================================================================
do $$
declare v_a uuid; v_c uuid; v_conv uuid; v_n int;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_c from t.fixtures where label='c';
  select id into v_conv from t.conv;

  set local role authenticated;

  -- C is a member of neither the DM nor its messages.
  perform t.become(v_c);
  perform t.eq('outsider cannot see the conversation',
    (select count(*)::int from public.conversations where id = v_conv), 0);
  perform t.eq('outsider cannot read messages',
    (select count(*)::int from public.messages where conversation_id = v_conv), 0);
  perform t.eq('outsider cannot read attachments',
    (select count(*)::int from public.message_attachments where conversation_id = v_conv), 0);
  perform t.eq('outsider cannot read membership',
    (select count(*)::int from public.conversation_members where conversation_id = v_conv), 0);

  begin
    perform public.send_message(v_conv, 'sneaking in', 'text', gen_random_uuid());
    perform t.ok('outsider cannot send', false, 'succeeded');
  exception when others then
    perform t.ok('outsider cannot send', true, sqlerrm);
  end;

  -- Regression: RLS does not inherit to partitions, and PostgREST
  -- exposes every table in `public`. Reading `messages_p7` instead of
  -- `messages` must not be a way around the policy.
  declare
    v_sum bigint := 0; v_part bigint; i int;
  begin
    for i in 0..15 loop
      execute format('select count(*) from public.messages_p%s', i) into v_part;
      v_sum := v_sum + v_part;
    end loop;
    perform t.eq('outsider cannot read messages via partitions directly', v_sum, 0::bigint);

    v_sum := 0;
    for i in 0..15 loop
      execute format('select count(*) from public.message_attachments_p%s', i) into v_part;
      v_sum := v_sum + v_part;
    end loop;
    perform t.eq('outsider cannot read attachments via partitions directly', v_sum, 0::bigint);

    v_sum := 0;
    for i in 0..7 loop
      execute format('select count(*) from public.notifications_p%s', i) into v_part;
      v_sum := v_sum + v_part;
    end loop;
    perform t.eq('outsider cannot read notifications via partitions directly', v_sum, 0::bigint);
  end;

  -- Direct writes to messages are revoked for everyone.
  begin
    insert into public.messages (conversation_id, seq, sender_id, kind, body)
    values (v_conv, 999, v_c, 'text', 'direct insert');
    perform t.ok('direct INSERT into messages denied', false, 'succeeded');
  exception when others then
    perform t.ok('direct INSERT into messages denied', true, 'privilege revoked');
  end;

  -- A member does see everything.
  perform t.become(v_a);
  select count(*)::int into v_n from public.messages where conversation_id = v_conv;
  perform t.ok('member reads the thread', v_n >= 4, format('%s messages', v_n));

  reset role;
end $$;


-- =====================================================================
-- 10. Column-level grants
-- =====================================================================
do $$
declare v_a uuid;
begin
  select id into v_a from t.fixtures where label='a';
  set local role authenticated;
  perform t.become(v_a);

  -- Allowed columns.
  update public.profiles set bio = 'CSE 2021. Building things.', interests = array['coding','music']
   where id = v_a;
  perform t.eq('own bio is writable',
    (select bio from public.profiles where id = v_a), 'CSE 2021. Building things.');

  -- Privileged columns are not granted.
  begin
    update public.profiles set trust_level = 'trusted' where id = v_a;
    perform t.ok('cannot self-promote trust_level', false, 'update succeeded');
  exception when others then
    perform t.ok('cannot self-promote trust_level', true, 'column grant held');
  end;

  begin
    update public.profiles set verification_level = 'ambassador' where id = v_a;
    perform t.ok('cannot self-verify', false, 'update succeeded');
  exception when others then
    perform t.ok('cannot self-verify', true, 'column grant held');
  end;

  begin
    update public.profiles set strike_count = 0 where id = v_a;
    perform t.ok('cannot clear own strikes', false, 'update succeeded');
  exception when others then
    perform t.ok('cannot clear own strikes', true, 'column grant held');
  end;

  -- Someone else's profile is off limits. RLS filters the row rather
  -- than raising, so the check is that the value did not change.
  begin
    update public.profiles set bio = 'hacked'
     where id = (select id from t.fixtures where label='b');
  exception when others then null;
  end;
  perform t.ok('cannot edit another profile',
    coalesce((select bio from public.profiles
               where id = (select id from t.fixtures where label='b')), '') <> 'hacked');

  -- Read state is writable; role is not.
  begin
    update public.conversation_members set role = 'owner'
     where user_id = v_a and conversation_id = (select id from t.conv);
    perform t.ok('cannot escalate own member role', false, 'update succeeded');
  exception when others then
    perform t.ok('cannot escalate own member role', true, 'column grant held');
  end;

  reset role;
end $$;


-- =====================================================================
-- 11. Soft delete  (exercises the messages_body_present exemption)
-- =====================================================================
do $$
declare v_a uuid; v_b uuid; v_conv uuid; v_msg uuid;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_conv from t.conv;

  set local role authenticated;
  perform t.become(v_a);

  select id into v_msg from public.messages
   where conversation_id = v_conv and sender_id = v_a and kind = 'text' order by seq limit 1;

  perform public.delete_message(v_conv, v_msg);
  perform t.ok('own text message soft-deletes',
    (select deleted_at from public.messages where conversation_id = v_conv and id = v_msg) is not null);
  perform t.eq('body cleared on delete',
    (select body from public.messages where conversation_id = v_conv and id = v_msg), null::text);
  perform t.eq('row survives for reply integrity',
    (select count(*)::int from public.messages where conversation_id = v_conv and id = v_msg), 1);

  -- Not someone else's message, though.
  perform t.become(v_b);
  begin
    perform public.delete_message(v_conv, (select id from public.messages
      where conversation_id = v_conv and sender_id = v_a and deleted_at is null limit 1));
    perform t.ok('cannot delete another member''s message', false, 'succeeded');
  exception when others then
    perform t.ok('cannot delete another member''s message', true, sqlerrm);
  end;

  reset role;
end $$;


-- =====================================================================
-- 12. Reply integrity across the partitioned FK
-- =====================================================================
do $$
declare v_a uuid; v_conv uuid; v_target uuid; v_reply public.messages%rowtype;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_conv from t.conv;

  set local role authenticated;
  perform t.become(v_a);

  select id into v_target from public.messages
   where conversation_id = v_conv and deleted_at is null order by seq desc limit 1;

  v_reply := public.send_message(v_conv, 'haan yehi', 'text', gen_random_uuid(), v_target);
  perform t.eq('reply links to its parent', v_reply.reply_to_id, v_target);

  -- A reply pointing outside the conversation must not link.
  begin
    perform public.send_message(v_conv, 'bad reply', 'text', gen_random_uuid(), gen_random_uuid());
    perform t.ok('cross-conversation reply rejected', false, 'succeeded');
  exception when others then
    perform t.ok('cross-conversation reply rejected', true, 'FK held');
  end;

  reset role;
end $$;


-- =====================================================================
-- 13. get_chat_list / get_messages
-- =====================================================================
do $$
declare v_a uuid; v_b uuid; v_conv uuid; r record; v_n int;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_conv from t.conv;

  set local role authenticated;
  perform t.become(v_b);

  select count(*)::int into v_n from public.get_chat_list();
  perform t.ok('chat list returns rows', v_n >= 1, format('%s rows', v_n));

  select * into r from public.get_chat_list() where conversation_id = v_conv;
  perform t.eq('DM row has the other student flattened in', r.other_user_id, v_a);
  perform t.eq('other name present', r.other_user_name, 'Aarav Sharma');
  perform t.eq('type is direct', r.type::text, 'direct');
  perform t.ok('unread count present', r.unread_count > 0, format('unread=%s', r.unread_count));

  -- Group threads show up in the same list.
  perform t.ok('department community appears in the list',
    exists (select 1 from public.get_chat_list() where type = 'group'));

  -- Pagination and attachment shaping.
  select count(*)::int into v_n from public.get_messages(v_conv);
  perform t.ok('get_messages returns history', v_n >= 4, format('%s messages', v_n));

  perform t.ok('attachments arrive as JSON',
    exists (select 1 from public.get_messages(v_conv) where jsonb_array_length(attachments) = 1));

  perform t.eq('deleted message body is withheld',
    (select count(*)::int from public.get_messages(v_conv)
      where deleted_at is not null and body is not null), 0);

  select count(*)::int into v_n from public.get_messages(v_conv, null, 2);
  perform t.eq('limit respected', v_n, 2);

  -- Keyset cursor: strictly older messages only.
  perform t.ok('cursor pages backwards',
    (select max(seq) from public.get_messages(v_conv, 3, 40)) < 3);

  reset role;
end $$;


-- =====================================================================
-- 14. Study groups: creation, capacity, membership
-- =====================================================================
do $$
declare
  v_a uuid; v_b uuid; v_c uuid; v_d uuid;
  v_sg public.study_groups%rowtype;
  v_n int;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_c from t.fixtures where label='c';
  select id into v_d from t.fixtures where label='d';

  set local role authenticated;
  perform t.become(v_a);

  v_sg := public.create_study_group('DBMS', 'DBMS end-sem prep', 'Unit 3 onwards', 'Tue & Thu 7pm', 'Block 6', 3::smallint);
  perform t.ok('study group created', v_sg.id is not null);
  perform t.ok('thread created with it', v_sg.conversation_id is not null);
  perform t.eq('host recorded', v_sg.host_id, v_a);

  perform t.eq('host is the owner of the thread',
    (select role::text from public.conversation_members
      where conversation_id = v_sg.conversation_id and user_id = v_a), 'owner');
  perform t.eq('member_count starts at 1',
    (select member_count from public.conversations where id = v_sg.conversation_id), 1);
  perform t.eq('group id matches conversation source_id',
    (select source_id from public.conversations where id = v_sg.conversation_id), v_sg.id);

  -- Two more join, filling it to 3.
  perform t.become(v_b);
  perform public.join_group(v_sg.conversation_id);
  perform t.become(v_c);
  perform public.join_group(v_sg.conversation_id);

  perform t.eq('member_count tracked joins',
    (select member_count from public.conversations where id = v_sg.conversation_id), 3);

  reset role;
  perform t.ok('group auto-closed when full',
    not (select is_open from public.study_groups where id = v_sg.id));

  -- The fourth is refused.
  set local role authenticated;
  perform t.become(v_d);
  begin
    perform public.join_group(v_sg.conversation_id);
    perform t.ok('capacity enforced', false, 'fourth member joined');
  exception when others then
    perform t.ok('capacity enforced', true, sqlerrm);
  end;

  -- Leaving frees a slot and reopens the group.
  perform t.become(v_c);
  perform public.leave_group(v_sg.conversation_id);
  reset role;
  perform t.eq('member_count tracked the leave',
    (select member_count from public.conversations where id = v_sg.conversation_id), 2);
  perform t.ok('group reopened', (select is_open from public.study_groups where id = v_sg.id));

  -- A joiner starts at the current head, not at the beginning of history.
  set local role authenticated;
  perform t.become(v_a);
  perform public.send_message(v_sg.conversation_id, 'kal 7 baje', 'text', gen_random_uuid());
  perform t.become(v_d);
  perform public.join_group(v_sg.conversation_id);
  select count(*)::int into v_n from public.get_messages(v_sg.conversation_id);
  perform t.eq('late joiner sees no backlog', v_n, 0);

  -- But does see what comes after.
  perform t.become(v_a);
  perform public.send_message(v_sg.conversation_id, 'confirm karo', 'text', gen_random_uuid());
  perform t.become(v_d);
  perform t.eq('late joiner sees new messages',
    (select count(*)::int from public.get_messages(v_sg.conversation_id)), 1);

  reset role;
end $$;


-- =====================================================================
-- 15. Notification fan-out
-- =====================================================================
do $$
declare
  v_a uuid; v_b uuid; v_conv uuid; v_msg public.messages%rowtype; v_n int;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_b from t.fixtures where label='b';
  select id into v_conv from t.conv;

  set local role authenticated;
  perform t.become(v_a);
  v_msg := public.send_message(v_conv, 'notification test', 'text', gen_random_uuid());
  reset role;

  v_n := public.fanout_message_notifications(v_conv, v_msg.seq);
  perform t.eq('one recipient notified', v_n, 1);

  perform t.eq('sender not notified',
    (select count(*)::int from public.notifications
      where user_id = v_a and target_id = v_conv), 0);

  perform t.ok('recipient notification created',
    exists (select 1 from public.notifications
             where user_id = v_b and kind = 'message' and target_id = v_conv));

  perform t.eq('deep link points at the thread',
    (select deep_link from public.notifications
      where user_id = v_b and target_id = v_conv order by id desc limit 1),
    '/chat/' || v_conv::text);

  -- Muting suppresses the row entirely.
  update public.conversation_members set muted_until = now() + interval '1 day'
   where conversation_id = v_conv and user_id = v_b;

  set local role authenticated;
  perform t.become(v_a);
  v_msg := public.send_message(v_conv, 'muted test', 'text', gen_random_uuid());
  reset role;
  perform t.eq('muted member not notified', public.fanout_message_notifications(v_conv, v_msg.seq), 0);

  update public.conversation_members set muted_until = null
   where conversation_id = v_conv and user_id = v_b;

  -- Notifications are read-only apart from read_at.
  set local role authenticated;
  perform t.become(v_b);
  update public.notifications set read_at = now() where user_id = v_b;
  perform t.ok('can mark own notification read', true);

  begin
    update public.notifications set title = 'spoofed' where user_id = v_b;
    perform t.ok('cannot rewrite notification content', false, 'update succeeded');
  exception when others then
    perform t.ok('cannot rewrite notification content', true, 'column grant held');
  end;

  perform t.eq('cannot see another student''s notifications',
    (select count(*)::int from public.notifications where user_id = v_a), 0);

  reset role;
end $$;


-- =====================================================================
-- 16. Storage policies
-- =====================================================================
do $$
declare
  v_a uuid; v_c uuid; v_conv uuid;
  v_ticket public.upload_tickets%rowtype;
begin
  select id into v_a from t.fixtures where label='a';
  select id into v_c from t.fixtures where label='c';
  select id into v_conv from t.conv;

  perform t.ok('chat-media bucket is private',
    not (select public from storage.buckets where id = 'chat-media'));
  perform t.eq('chat-media size limit is 5 MB',
    (select file_size_limit from storage.buckets where id = 'chat-media'), 5242880::bigint);
  perform t.ok('avatars bucket is public',
    (select public from storage.buckets where id = 'avatars'));

  set local role authenticated;
  perform t.become(v_a);

  v_ticket := public.create_upload_ticket(v_conv, 'photo', 'Block 6 library.jpg', 'image/jpeg', 3774873);

  -- With a live ticket the upload is allowed.
  insert into storage.objects (bucket_id, name, owner) values ('chat-media', v_ticket.object_path, v_a);
  perform t.ok('ticketed upload accepted by storage policy', true);

  -- Without one it is not.
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('chat-media', v_conv::text || '/' || v_a::text || '/forged.jpg', v_a);
    perform t.ok('unticketed upload refused by storage policy', false, 'insert succeeded');
  exception when others then
    perform t.ok('unticketed upload refused by storage policy', true, 'policy held');
  end;

  -- A member can read the object.
  perform t.eq('member can read chat media',
    (select count(*)::int from storage.objects
      where bucket_id = 'chat-media' and name = v_ticket.object_path), 1);

  -- An outsider cannot, even knowing the exact path.
  perform t.become(v_c);
  perform t.eq('outsider cannot read chat media even with the path',
    (select count(*)::int from storage.objects
      where bucket_id = 'chat-media' and name = v_ticket.object_path), 0);

  -- Avatars are namespaced by user id.
  perform t.become(v_a);
  insert into storage.objects (bucket_id, name, owner)
  values ('avatars', v_a::text || '/me.jpg', v_a);
  perform t.ok('own avatar upload accepted', true);

  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('avatars', v_c::text || '/hijack.jpg', v_a);
    perform t.ok('cannot upload into another user''s avatar folder', false, 'insert succeeded');
  exception when others then
    perform t.ok('cannot upload into another user''s avatar folder', true, 'policy held');
  end;

  reset role;
end $$;


-- =====================================================================
-- 17. Rate limiting
-- =====================================================================
do $$
declare
  v_x uuid; v_y uuid; v_conv uuid; v_i int; v_n int; v_blocked boolean := false;
begin
  -- Fresh pair so earlier tests' message counts do not interfere.
  v_x := t.signup('21bcs9001@cuchd.in', 'Rate Test X');
  v_y := t.signup('21bcs9002@cuchd.in', 'Rate Test Y');
  update public.profiles set allow_dm_from_anyone = true where id = v_y;

  set local role authenticated;
  perform t.become(v_x);
  v_conv := public.get_or_create_direct_conversation(v_y);

  -- Counted with an explicit variable: a plpgsql FOR loop declares its
  -- own counter that shadows the outer one, so the outer stays NULL.
  v_i := 0;
  for v_n in 1..35 loop
    begin
      perform public.send_message(v_conv, 'msg ' || v_n, 'text', gen_random_uuid());
      v_i := v_i + 1;
    exception when others then
      v_blocked := true;
      exit;
    end;
  end loop;

  perform t.ok('message flood rate-limited', v_blocked, format('%s sent before the limit bit', v_i));
  perform t.ok('limit is 30/min, so it allowed ~30', v_i between 25 and 31, format('sent=%s', v_i));

  reset role;
end $$;


-- =====================================================================
-- 18. Schema-level sanity
-- =====================================================================
do $$
declare v_n int; v_missing text;
begin
  -- Every table in public must have RLS on.
  select count(*)::int, string_agg(t.tablename, ', ')
    into v_n, v_missing
  from pg_tables t
  where t.schemaname = 'public'
    and not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where c.relname = t.tablename and n.nspname = 'public' and c.relrowsecurity
    );
  perform t.eq('every public table has RLS enabled (partitions included)', v_n, 0);
  if v_n > 0 then
    perform t.ok('  tables missing RLS: ' || v_missing, false);
  end if;

  -- Partitioning landed as designed.
  perform t.eq('messages has 16 partitions',
    (select count(*)::int from pg_inherits where inhparent = 'public.messages'::regclass), 16);
  perform t.eq('message_attachments has 16 partitions',
    (select count(*)::int from pg_inherits where inhparent = 'public.message_attachments'::regclass), 16);
  perform t.eq('notifications has 8 partitions',
    (select count(*)::int from pg_inherits where inhparent = 'public.notifications'::regclass), 8);

  perform t.eq('messages is hash partitioned on conversation_id',
    (select pg_get_partkeydef('public.messages'::regclass)), 'HASH (conversation_id)');

  -- Realtime publication.
  -- Realtime must publish under the PARENT name. With
  -- publish_via_partition_root off, changes arrive as `messages_p7` and
  -- a client subscribed to `public:messages` receives nothing.
  perform t.ok('messages published for realtime under the parent name',
    exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'));
  perform t.ok('publication publishes via partition root',
    (select pubviaroot from pg_publication where pubname = 'supabase_realtime'));
  perform t.eq('partitions are not published individually',
    (select count(*)::int from pg_publication_tables
      where pubname = 'supabase_realtime' and tablename like 'messages\_p%'), 0);

  -- Reference data.
  perform t.eq('22 CU programs seeded',
    (select count(*)::int from public.programs), 22);
  perform t.ok('department communities seeded',
    (select count(*)::int from public.communities where is_department) >= 15);
  perform t.ok('tags seeded', (select count(*)::int from public.tags) >= 40);

  -- The year helpers are inverses of each other.
  perform t.eq('study_year/admission_year round-trip',
    public.study_year(public.admission_year_for_study_year(3)), 3);
end $$;


-- =====================================================================
-- Report
-- =====================================================================
\echo ''
\echo '================ FAILURES ================'
select id, name, detail from t.results where not passed order by id;

\echo ''
\echo '================ SUMMARY ================='
select
  count(*) filter (where passed)     as passed,
  count(*) filter (where not passed) as failed,
  count(*)                            as total
from t.results;
