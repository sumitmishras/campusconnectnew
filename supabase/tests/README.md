# Verification suite

150 assertions over the schema: the five checks named in DATABASE.md plus the
RLS, constraint and trigger behaviour they depend on.

## Against a real Supabase project

`00_local_supabase_shim.sql` is **not** needed — Supabase already provides
`auth`, `storage` and the roles. Run only the suite:

```bash
psql "$SUPABASE_DB_URL" -f tests/90_verification.sql
```

Use a throwaway project or a branch. The suite creates real users and messages
and does not clean up after itself.

## Against a local Postgres (no Docker needed)

Any PostgreSQL 14+ works. The shim recreates just enough of Supabase —
`auth.users`, `auth.uid()`, `storage.buckets`/`objects`,
`storage.foldername()`, the `anon`/`authenticated`/`service_role` roles, the
`supabase_realtime` publication, and Supabase's default grants on `public`.

```bash
createdb cc_test
psql -d cc_test -f tests/00_local_supabase_shim.sql
for f in migrations/*.sql; do psql -d cc_test -v ON_ERROR_STOP=1 -f "$f"; done
psql -d cc_test -f tests/90_verification.sql
```

`wal_level = logical` is needed for the realtime publication assertions.
`pg_cron` is not required — migration 0010 skips the schedules with a notice.

## Reading the output

The last two queries print failures and then a summary. A clean run:

```
================ FAILURES ================
 id | name | detail
----+------+--------
(0 rows)

================ SUMMARY =================
 passed | failed | total
--------+--------+-------
    150 |      0 |   150
```

`passed + failed` must equal `total`. If it does not, an assertion evaluated to
NULL — that is a broken test, not a pass. Find it with:

```sql
select id, name, detail from t.results where passed is null;
```

## How impersonation works

Exactly the way PostgREST does it, so the policies under test are the ones that
run in production:

```sql
set local role authenticated;
select t.become('<user uuid>');   -- sets request.jwt.claim.sub
```

`reset role` returns to superuser, which bypasses RLS — anything asserting an
RLS outcome must run inside `set local role authenticated`.

## What it covers

| Section | Checks |
|---|---|
| 1 | Signup trigger: profile shell, university-id parsing, non-CU domains refused |
| 2 | Department community auto-join, member_count trigger |
| 3 | Connection state machine — only the addressee can accept |
| 4 | DM gate: no connection, no chat; creation is race-safe and idempotent |
| 5 | `send_message`, seq allocation, **idempotent retry** |
| 6 | Unread arithmetic, `mark_read` never rewinds |
| 7 | Attachments: **5 MB limit**, ticket-backed uploads, mime allow-list |
| 8 | **Blocking** — thread goes read-only both ways, connection severed |
| 9 | RLS isolation, including **direct partition access** |
| 10 | Column-level grants: no self-promotion to `trusted` |
| 11 | Soft delete |
| 12 | Reply integrity across the partitioned FK |
| 13 | `get_chat_list` / `get_messages` shape and pagination |
| 14 | Study groups: creation, capacity, late-joiner backlog |
| 15 | Notification fan-out, mute handling |
| 16 | Storage policies for `chat-media` and `avatars` |
| 17 | Rate limiting |
| 18 | Schema sanity: RLS everywhere, partition counts, seed data |

## If you add a partition

Section 18 asserts every table in `public` has RLS enabled, partitions
included. That check exists because RLS does **not** inherit from a partitioned
parent, and PostgREST exposes partitions as their own endpoints — see the
comment above the partition loop in `0008_rls_policies.sql`. Any partition added
later must have RLS enabled, or this test will catch it.
