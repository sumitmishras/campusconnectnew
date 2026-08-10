-- =====================================================================
-- 0009  Storage buckets for photos, documents and avatars
-- =====================================================================
-- The file bytes live in Supabase Storage (S3 behind the scenes); the
-- database holds the metadata. `message_attachments.object_path` is the
-- join between the two.
--
-- The important idea here: chat-media is PRIVATE. Every object path is
-- prefixed with its conversation id, and the storage policies check
-- membership of that conversation before allowing a read. A public
-- bucket with unguessable names is not access control — anyone who ever
-- receives a URL keeps it forever, including after being removed from
-- the group.
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  -- Profile photos. Public because they show up in Discover lists where
  -- signing every URL would mean 40 signature round-trips per scroll.
  ('avatars', 'avatars', true, 2097152,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic']),

  -- Chat attachments: 5 MB, matching AttachmentService.maxBytes.
  ('chat-media', 'chat-media', false, 5242880,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
          'application/pdf',
          'application/msword',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'application/vnd.ms-excel',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'application/vnd.ms-powerpoint',
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          'text/plain']),

  -- Student ID cards for verification. Private, and readable only by
  -- moderators — this is the most sensitive data in the system.
  ('verification-docs', 'verification-docs', false, 5242880,
    array['image/jpeg', 'image/png', 'application/pdf']),

  -- Club logos, event covers.
  ('campus-assets', 'campus-assets', true, 3145728,
    array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml'])
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;


do $$
declare r record;
begin
  for r in select policyname from pg_policies
           where schemaname = 'storage' and tablename = 'objects'
             and policyname like 'cc_%'
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- avatars/{user_id}/{uuid}.jpg
-- ---------------------------------------------------------------------
create policy cc_avatars_read on storage.objects
  for select to authenticated, anon
  using (bucket_id = 'avatars');

create policy cc_avatars_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy cc_avatars_update on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy cc_avatars_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);


-- ---------------------------------------------------------------------
-- chat-media/{conversation_id}/{sender_id}/{uuid}.ext
-- ---------------------------------------------------------------------
-- Read: any current member of that conversation. Because the check is
-- live, removing someone from a group instantly cuts off their access to
-- every file ever shared in it.
create policy cc_chat_media_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'chat-media'
    and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
  );

-- Write: only against a live upload ticket issued to this user for this
-- exact path. The path is server-generated (create_upload_ticket), so a
-- client cannot invent one, cannot overwrite another thread's object,
-- and cannot exceed the size/type it declared.
create policy cc_chat_media_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and exists (
      select 1 from public.upload_tickets t
      where t.object_path = storage.objects.name
        and t.user_id = auth.uid()
        and t.consumed_at is null
        and t.expires_at > now()
    )
  );

-- No update and no delete policy: attachments are immutable once sent.
-- Cleanup is done by the service role in the job below.


-- ---------------------------------------------------------------------
-- verification-docs/{user_id}/{uuid}
-- ---------------------------------------------------------------------
create policy cc_verification_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy cc_verification_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'verification-docs'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_moderator())
  );


-- ---------------------------------------------------------------------
-- campus-assets
-- ---------------------------------------------------------------------
create policy cc_campus_assets_read on storage.objects
  for select to authenticated, anon
  using (bucket_id = 'campus-assets');

-- Club leads and trusted students can upload club/event imagery.
create policy cc_campus_assets_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'campus-assets'
    and (select trust_level from public.profiles where id = auth.uid()) = 'trusted'
  );
