-- =====================================================================
-- 0010  Notification fan-out, retention jobs, scheduling
-- =====================================================================


-- ---------------------------------------------------------------------
-- Message notification fan-out
-- ---------------------------------------------------------------------
-- Deliberately a function the chat server calls after the send commits,
-- NOT an AFTER INSERT trigger on messages.
--
-- A trigger would run inside send_message's transaction: a message to a
-- 500-member club thread would do 500 notification inserts before the
-- sender's own request could return, while still holding the row lock on
-- `conversations` that serialises that thread. One chatty group would
-- throttle itself, and a failure in the fan-out would roll back a
-- message the sender already saw as sent.
--
-- Sending is the latency-critical path; being notified is not.
create or replace function public.fanout_message_notifications(
  p_conversation_id uuid,
  p_seq             bigint
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_msg     public.messages%rowtype;
  v_conv    public.conversations%rowtype;
  v_sender  text;
  v_title   text;
  v_inserted integer;
begin
  select * into v_msg from public.messages
   where conversation_id = p_conversation_id and seq = p_seq;
  if not found then
    return 0;
  end if;

  select * into v_conv from public.conversations where id = p_conversation_id;
  select full_name into v_sender from public.profiles where id = v_msg.sender_id;

  v_title := case
    when v_conv.type = 'direct' then coalesce(v_sender, 'New message')
    else coalesce(v_conv.title, 'Group') || ' · ' || coalesce(v_sender, 'Someone')
  end;

  with recipients as (
    select m.user_id
    from public.conversation_members m
    join public.profiles p on p.id = m.user_id
    left join public.notification_settings ns on ns.user_id = m.user_id
    where m.conversation_id = p_conversation_id
      and m.left_at is null
      and m.user_id <> v_msg.sender_id
      and p.deleted_at is null
      -- Muted threads and the "messages off" preference are honoured
      -- here rather than at push time, so the row is never created.
      and (m.muted_until is null or m.muted_until < now())
      and coalesce(ns.messages, true)
      and (
        m.notify_level = 'all'
        or (m.notify_level = 'mentions' and m.user_id = any (v_msg.mentions))
      )
      -- A blocked sender's messages never notify.
      and not public.is_blocked_either_way(m.user_id, v_msg.sender_id)
  )
  insert into public.notifications (user_id, kind, title, body, actor_id, target_type, target_id, deep_link)
  select
    r.user_id, 'message', v_title,
    coalesce(v_conv.last_message_preview, ''),
    v_msg.sender_id, 'conversation', p_conversation_id,
    '/chat/' || p_conversation_id::text
  from recipients r;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

revoke all on function public.fanout_message_notifications(uuid, bigint) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Orphaned upload cleanup
-- ---------------------------------------------------------------------
-- A ticket that expired without a message referencing it means bytes are
-- sitting in storage with nothing pointing at them — someone opened the
-- picker and backed out, or the send failed after the upload. Without
-- this the bucket grows forever.
create or replace function public.cleanup_orphaned_uploads()
returns table (bucket text, object_path text)
language sql
security definer
set search_path = public
as $$
  with doomed as (
    delete from public.upload_tickets t
    where t.consumed_at is null
      and t.expires_at < now() - interval '1 hour'
    returning t.bucket, t.object_path
  )
  select * from doomed;
$$;

comment on function public.cleanup_orphaned_uploads() is
  'Returns the storage objects to delete. The caller must then remove them '
  'from the bucket — SQL cannot delete bytes out of Storage.';


-- ---------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------
create or replace function public.run_retention()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_notifications bigint := 0;
  v_views         bigint := 0;
  v_limits        bigint := 0;
  v_audit         bigint := 0;
  v_n             bigint;
begin
  -- Notifications older than 60 days, in batches so the job never holds
  -- a long transaction against a partitioned hot table.
  --
  -- Batched by primary key, NOT by ctid: `notifications` is partitioned,
  -- and a ctid is only unique within one partition. Collecting ctids
  -- across partitions and deleting by them would match the wrong rows.
  loop
    delete from public.notifications n
     using (
       select user_id, id from public.notifications
       where created_at < now() - interval '60 days'
       limit 10000
     ) d
     where n.user_id = d.user_id and n.id = d.id;
    get diagnostics v_n = row_count;
    v_notifications := v_notifications + v_n;
    exit when v_n = 0;
  end loop;

  delete from public.profile_views where view_date < current_date - 90;
  get diagnostics v_views = row_count;

  delete from public.rate_limits where window_start < now() - interval '2 days';
  get diagnostics v_limits = row_count;

  delete from public.audit_log where created_at < now() - interval '1 year';
  get diagnostics v_audit = row_count;

  return jsonb_build_object(
    'notifications_deleted', v_notifications,
    'profile_views_deleted', v_views,
    'rate_limits_deleted',   v_limits,
    'audit_rows_deleted',    v_audit
  );
end;
$$;


-- ---------------------------------------------------------------------
-- Presence decay
-- ---------------------------------------------------------------------
-- A phone that loses signal never sends a disconnect, so "online" has to
-- expire on a timer or the app fills up with ghosts.
create or replace function public.expire_stale_presence()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_n integer;
begin
  update public.user_presence
     set is_online = false, node_id = null
   where is_online and last_active < now() - interval '2 minutes';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;


-- ---------------------------------------------------------------------
-- Hard delete a student  (DPDP Act / "delete my account")
-- ---------------------------------------------------------------------
-- Their messages are NOT deleted with them — that would gut other
-- people's conversations. They are anonymised: sender_id goes null (the
-- FK is ON DELETE SET NULL) and the body of any personal message goes
-- with the profile. This is the standard reading of erasure for
-- multi-party communications.
create or replace function public.purge_deleted_profiles()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_n  integer := 0;
begin
  for v_id in
    select id from public.profiles
    where deleted_at is not null and deleted_at < now() - interval '30 days'
  loop
    update public.messages set body = null, deleted_at = coalesce(deleted_at, now())
     where sender_id = v_id;

    delete from auth.users where id = v_id;   -- cascades to profiles
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;


-- ---------------------------------------------------------------------
-- Scheduling
-- ---------------------------------------------------------------------
-- pg_cron is available on Supabase but must be enabled once from the
-- dashboard (Database → Extensions) before these schedules will take.
-- The DO block keeps this migration from failing if it is not on yet.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('cc-expire-presence', '* * * * *',
      $job$ select public.expire_stale_presence(); $job$);

    perform cron.schedule('cc-retention', '30 3 * * *',
      $job$ select public.run_retention(); $job$);

    perform cron.schedule('cc-purge-profiles', '0 4 * * *',
      $job$ select public.purge_deleted_profiles(); $job$);
  else
    raise notice 'pg_cron is not enabled — skipping job schedules. '
                 'Enable it in the Supabase dashboard and re-run this migration.';
  end if;
exception when others then
  raise notice 'Could not register cron jobs: %', sqlerrm;
end $$;


-- ---------------------------------------------------------------------
-- Statistics targets
-- ---------------------------------------------------------------------
-- The planner's default 100-bucket histogram is too coarse for these
-- columns once the tables are large, and a bad estimate on
-- conversation_id is the difference between an index scan and a
-- sequential scan over a partition.
alter table public.messages alter column conversation_id set statistics 1000;
alter table public.conversation_members alter column user_id set statistics 1000;
alter table public.notifications alter column user_id set statistics 1000;
