-- =====================================================================
-- 0015  Push notifications — V1
-- =====================================================================
-- Two events only: a new chat message, and an incoming connection
-- request. Everything else (events, polls, clubs, likes, profile views)
-- is deliberately out of scope.
--
-- Almost none of this is new. `notifications`, `notification_settings`
-- and `user_devices` were all built in 0002/0006, and
-- `fanout_message_notifications()` in 0010 already contains the entire
-- message rule set — sender excluded, muted threads skipped, blocked
-- senders skipped, `notify_level` honoured, deep link written. It was
-- simply never called: DATABASE.md hands that job to the Node chat
-- server, which does not exist yet.
--
-- So this migration is three small things:
--   1. call the existing fanout when a message lands,
--   2. write the one notification kind that had no producer at all,
--   3. poke the Edge Function that turns a row into an FCM message.
-- =====================================================================


create schema if not exists private;


-- ---------------------------------------------------------------------
-- 1. New message
-- ---------------------------------------------------------------------
-- The trigger is on `conversations`, not on `messages`, and the reason
-- is ordering inside send_message(): the message row is inserted at
-- step 7, its attachments at step 8, and the conversation preview at
-- step 9. A trigger on `messages` would therefore fire before the
-- attachment rows exist, and a shared PDF would notify as an empty body
-- because the file name it needs is not written yet.
--
-- Step 9 is the last thing that happens, it happens exactly once per
-- message, and it carries both the conversation id and the new head —
-- which is precisely what the fanout takes.
create or replace function public.tg_notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Step 6 of send_message() also updates this row (to allocate `seq`),
  -- so the timestamp is what separates "a message was sent" from "the
  -- counter moved". Without this the fanout would run twice per message.
  if new.last_message_at is distinct from old.last_message_at then
    perform public.fanout_message_notifications(new.id, new.last_seq);
  end if;
  return null;
exception when others then
  -- A notification is a courtesy; the message is the product. This trigger
  -- runs inside send_message()'s transaction, so an unhandled error here
  -- would roll the message itself back — a student would be told their
  -- message failed to send because a notification row could not be written.
  raise warning 'message notification fanout failed for %: %', new.id, sqlerrm;
  return null;
end;
$$;

create or replace trigger notify_new_message
  after update of last_message_at on public.conversations
  for each row execute function public.tg_notify_new_message();


-- ---------------------------------------------------------------------
-- 2. Connection request
-- ---------------------------------------------------------------------
-- Unlike messages, this had no producer at all. It is a plain client
-- INSERT into `connections` (see `connections_send` in 0008), so a
-- trigger is the only place that catches every path into the table.
--
-- Only the arrival of a request notifies. Accept/decline/withdraw are
-- state changes on an existing row and are out of scope for V1.
create or replace function public.tg_notify_connection_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_name text;
begin
  if new.state <> 'pending' then
    return null;
  end if;

  select full_name into v_name from public.profiles where id = new.requester_id;

  -- Written as INSERT…SELECT with the gates in the WHERE clause, the same
  -- shape the message fanout uses: a suppressed notification is one that
  -- was never created, so there is no row for a push job to find later.
  insert into public.notifications (
    user_id, kind, title, body, actor_id, target_type, target_id, deep_link
  )
  select
    new.addressee_id,
    'connection',
    coalesce(v_name, 'Someone') || ' sent you a connection request',
    coalesce(nullif(trim(new.purpose), ''), ''),
    new.requester_id,
    'connection',
    new.id,
    '/connections'
  where exists (
      select 1 from public.profiles p
      where p.id = new.addressee_id and p.deleted_at is null
    )
    and coalesce((
      select ns.connections from public.notification_settings ns
      where ns.user_id = new.addressee_id
    ), true)
    and not public.is_blocked_either_way(new.addressee_id, new.requester_id);

  return null;
exception when others then
  -- As above: a failed notification must never turn into "your connection
  -- request could not be sent".
  raise warning 'connection notification failed for %: %', new.id, sqlerrm;
  return null;
end;
$$;

create or replace trigger notify_connection_request
  after insert on public.connections
  for each row execute function public.tg_notify_connection_request();


-- ---------------------------------------------------------------------
-- 3. Handing the row to FCM
-- ---------------------------------------------------------------------
-- The endpoint and the shared secret are database settings rather than a
-- table, because a table in `public` is reachable through PostgREST and
-- this secret is what lets the caller send a push to anyone. Set them
-- once, on the deployed database:
--
--   alter database postgres
--     set app.push_endpoint = 'http://kong:8000/functions/v1/push-notify';
--   alter database postgres
--     set app.push_secret = '<the same value as PUSH_SHARED_SECRET>';
--
-- `kong:8000` is the container-network address, so the request never
-- leaves the host and never touches TLS or the public domain.
do $$ begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net not available — pushes will not dispatch. '
               'Install it, or run a worker against retry_pending_pushes().';
end $$;


create or replace function private.dispatch_push(
  p_user_id         uuid,
  p_notification_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare
  v_url    text := current_setting('app.push_endpoint', true);
  v_secret text := current_setting('app.push_secret', true);
begin
  -- Unset on a machine that has no push configured — a local database, or
  -- a deploy where the Edge Function is not up yet. The notification row
  -- still exists and the in-app list still shows it.
  if coalesce(v_url, '') = '' then
    return;
  end if;

  perform net.http_post(
    url     := v_url,
    body    := jsonb_build_object(
                 'notification_id', p_notification_id,
                 'user_id', p_user_id
               ),
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || coalesce(v_secret, '')
               ),
    timeout_milliseconds := 5000
  );
exception when others then
  -- pg_net missing, or the call itself refused. `pushed_at` stays null,
  -- which is exactly what `notifications_push_pending_idx` (0006) indexes
  -- and what the sweep below picks back up. A failed push must never
  -- fail the message or the connection request that caused it.
  null;
end;
$$;

revoke all on function private.dispatch_push(uuid, uuid) from public, anon, authenticated;


create or replace function public.tg_dispatch_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.dispatch_push(new.user_id, new.id);
  return null;
exception when others then
  raise warning 'push dispatch failed for %: %', new.id, sqlerrm;
  return null;
end;
$$;

create or replace trigger dispatch_push
  after insert on public.notifications
  for each row execute function public.tg_dispatch_push();


-- Anything the trigger could not hand over — the function was restarting,
-- pg_net dropped it, FCM was down. One minute old so a push in flight is
-- not sent twice, one day old at the outside because a notification that
-- late is noise rather than news.
create or replace function public.retry_pending_pushes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r       record;
  v_count integer := 0;
begin
  for r in
    select user_id, id from public.notifications
    where pushed_at is null
      and created_at < now() - interval '1 minute'
      and created_at > now() - interval '1 day'
    order by created_at
    limit 200
  loop
    perform private.dispatch_push(r.user_id, r.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.retry_pending_pushes() from public, anon, authenticated;


do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('cc-push-retry');
  end if;
exception when others then null; end $$;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('cc-push-retry', '* * * * *',
      $job$ select public.retry_pending_pushes(); $job$);
  else
    raise notice 'pg_cron is not enabled — push retries will not run.';
  end if;
exception when others then
  raise notice 'Could not register the push retry job: %', sqlerrm;
end $$;


-- ---------------------------------------------------------------------
-- 4. Device registration
-- ---------------------------------------------------------------------
-- `user_devices` has existed since 0002; what it never had was a way in.
-- A function rather than table grants, for the same reason every chat
-- write is a function: the client should be able to register *its own*
-- handset and nothing else, and a table grant would also let it read the
-- token of every device it can see through `devices_own`.
create or replace function public.register_push_device(
  p_token    text,
  p_platform text,
  p_locale   text default null,
  p_model    text default null,
  p_version  text default null
)
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
  if coalesce(trim(p_token), '') = '' then
    return;
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'Unknown platform %', p_platform using errcode = '22023';
  end if;

  -- ON CONFLICT on the token, not on the user: one student may carry two
  -- handsets, and one handset may be handed to another student. The token
  -- identifies the handset, so re-pointing it is the correct answer to
  -- both.
  insert into public.user_devices (
    user_id, push_token, platform, locale, device_model, app_version,
    last_seen_at, push_enabled
  )
  values (v_me, p_token, p_platform, p_locale, p_model, p_version, now(), true)
  on conflict (push_token) do update
    set user_id      = excluded.user_id,
        platform     = excluded.platform,
        locale       = excluded.locale,
        device_model = excluded.device_model,
        app_version  = excluded.app_version,
        last_seen_at = now(),
        push_enabled = true;
end;
$$;

grant execute on function
  public.register_push_device(text, text, text, text, text) to authenticated;
