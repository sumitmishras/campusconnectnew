-- =====================================================================
-- 0013 — Realtime gaps
-- =====================================================================
-- Two things 0008 left the app unable to do live. Both of them show up to
-- a student as "nothing happens until I pull to refresh".
--
--   1. `connections` is not published, so a request arriving is invisible
--      until the Connections tab is re-fetched by hand. Nothing else could
--      stand in for it either: the only row that gets written when someone
--      taps Connect is the `connections` row itself — `notifications` is
--      written for new *messages* only (0010), never for requests.
--
--   2. `public.messages` — the partitioned parent — never got REPLICA
--      IDENTITY FULL. 0008 set it on the partitions and said in its own
--      comment that the parent was covered, but with
--      `publish_via_partition_root = true` the change is published under
--      the ROOT's identity, so the parent is exactly what has to carry it.
--      Without it an UPDATE arrives with no old row and a soft-deleted
--      message does not disappear on the other side.
--
-- Presence is deliberately NOT published: the live dot belongs to the
-- presence channel, and the stale-dot bug it was showing is a client that
-- never applied the channel's opening snapshot. That fix is in
-- `UserProvider` / `ChatProvider`, not here.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 1. Connection requests
-- ---------------------------------------------------------------------
-- RLS (`connections_read`, 0008) already limits this to rows where the
-- student is the requester or the addressee, and Realtime honours it, so
-- publishing the table does not widen what anyone can see.
do $$ begin
  alter publication supabase_realtime add table public.connections;
exception when duplicate_object then null; end $$;

-- Not partitioned, so the parent is the whole story. FULL rather than the
-- default: the client needs to tell "pending -> accepted" from
-- "pending -> declined", and the new row alone does not say what it was.
alter table public.connections replica identity full;


-- ---------------------------------------------------------------------
-- 2. Messages: identity on the partition ROOT
-- ---------------------------------------------------------------------
-- Safe to repeat; 0008's loop over the partitions stays as it is.
alter table public.messages replica identity full;
