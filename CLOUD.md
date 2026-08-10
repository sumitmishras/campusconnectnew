# Campus Connect — AWS Self-Hosted Infrastructure

**Built:** 8 August 2026
**Account:** `960154456591` · **Region:** `us-east-1`
**Status:** Live. All 13 migrations applied, all 12 containers healthy, TLS valid.

This document records what was provisioned, why each choice was made, how to
operate it, and what is still outstanding. Everything here was built from
scratch — the project previously ran on hosted Supabase project
`rlvbpwqrsiemhqfndnkz`, which is untouched and can still be used as a fallback.

---

## 1. What this replaces

| Before | After |
|---|---|
| Hosted Supabase (`*.supabase.co`) | Self-hosted Supabase on your EC2 |
| Supabase-managed Postgres | `supabase/postgres:17.6.1.136` in Docker |
| Supabase Storage (their S3) | Your S3 bucket, your account |
| Supabase's built-in mailer | Amazon SES via SMTP |
| Their TLS | Let's Encrypt via Caddy |

**Nothing in `lib/` or `supabase/migrations/` was modified.** The only project
file changed is `dart_define.json` (old one saved as
`dart_define.hosted-supabase.json.bak`). `flutter analyze` is still clean and
all 263 tests still pass against the new configuration.

---

## 2. Architecture

```
                        Internet
                            │
                            ▼
              ┌──────────────────────────┐
              │  Elastic IP              │
              │  13.223.251.151          │
              └────────────┬─────────────┘
                           │ :80 :443
                  ┌────────▼────────┐
                  │  Caddy          │  Let's Encrypt, auto-renew
                  │  (TLS termination)│
                  └────────┬────────┘
                           │
            ┌──────────────┴──────────────┐
            │                             │
   /auth/v1  /rest/v1  /realtime/v1       │  everything else
   /storage/v1  /functions/v1             │  (basic auth)
            │                             │
            ▼                             ▼
      ┌──────────┐                  ┌──────────┐
      │  Kong    │                  │  Studio  │
      │ (gateway)│                  │ (dashboard)│
      └─────┬────┘                  └──────────┘
            │
   ┌────────┼────────┬─────────┬──────────┬──────────┐
   ▼        ▼        ▼         ▼          ▼          ▼
 GoTrue  PostgREST Realtime  Storage   imgproxy  Edge Runtime
   │        │        │         │
   └────────┴────┬───┴─────────┘
                 ▼                        ▼
          ┌─────────────┐          ┌─────────────┐
          │  Postgres 17│          │  Amazon S3  │
          │  + pg_cron  │          │  (objects)  │
          └─────────────┘          └─────────────┘
                 │
                 ▼
          ┌─────────────┐
          │ Amazon SES  │  ← OTP mail (SMTP :587)
          └─────────────┘
```

All twelve containers run on one `t3.medium`. Postgres data lives on the
instance's encrypted EBS volume; uploaded objects live in S3.

---

## 3. AWS resources created

### Networking
| Resource | ID | Notes |
|---|---|---|
| VPC | `vpc-0f549ad31ee6a8e77` | `10.20.0.0/16`, DNS hostnames on |
| Public subnet | `subnet-0ee34d97fba34c037` | `10.20.1.0/24`, us-east-1a, auto-assign public IP |
| Internet gateway | `igw-0ad366486a753c125` | |
| Route table | `rtb-0215f5e9009a36be2` | `0.0.0.0/0` → IGW |
| Security group | `sg-064cf48a919e9903a` | see below |
| Elastic IP | `eipalloc-0b9e8c380241ef2ee` | **13.223.251.151** |

A dedicated VPC rather than the default one, with a single public subnet and no
NAT gateway — a NAT would add ~$32/month and buys nothing for a one-host
deployment that needs to be publicly reachable anyway.

**Security group rules (inbound):**

| Port | Source | Why |
|---|---|---|
| 22 | `38.183.13.199/32` | SSH, locked to your IP at build time |
| 80 | `0.0.0.0/0` | Let's Encrypt ACME challenge + HTTPS redirect |
| 443 | `0.0.0.0/0` | The API itself |

Postgres (5432) is **not** exposed. Reach it through an SSH tunnel — see §7.

> **If your home/office IP changes, SSH will stop working.** Fix:
> ```bash
> MYIP=$(curl -s https://checkip.amazonaws.com)
> aws ec2 authorize-security-group-ingress --group-id sg-064cf48a919e9903a \
>   --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MYIP/32,Description='SSH admin'}]"
> ```

### Compute
| Property | Value |
|---|---|
| Instance | `i-00c0a97e8ff92aa5e` |
| Type | `t3.medium` (2 vCPU, 4 GB) |
| AMI | `ami-052355af2a014bd2c` — Ubuntu 24.04 LTS |
| Storage | 100 GB gp3, **encrypted**, delete-on-termination |
| IMDS | IMDSv2 required, hop limit 2 |
| Instance profile | `campus-connect-profile` |
| SSH key | `campus-connect` (ed25519) → `~/.ssh/campus-connect.pem` |

Hop limit 2 is deliberate: it is what lets the Storage **container** reach the
instance metadata service and pick up IAM role credentials. With the default
hop limit of 1 the container cannot, and you would be forced to put long-lived
AWS keys in a file on the box.

A 2 GB swapfile was added at boot. 4 GB is enough for this stack in steady
state (currently ~1.7 GB used) but Postgres and Realtime can both spike, and an
OOM kill of the database is a much worse outcome than a few seconds of swap.

### Storage
| Resource | Value |
|---|---|
| S3 bucket | `campus-connect-storage-960154456591` |
| Public access | Fully blocked (all four settings) |
| Encryption | SSE-S3 (AES256) |
| Versioning | Enabled |

The bucket is private at the AWS level. "Public" buckets in the app sense
(`avatars`, `campus-assets`) are served through the Storage API's public URL
route, not by making S3 objects world-readable. Versioning is on so a bad
delete is recoverable.

Objects are keyed `campus-connect/<bucket>/<path>/<uuid>`.

### IAM
| Resource | Purpose |
|---|---|
| Role `campus-connect-ec2-role` | Attached to the instance |
| Inline policy `campus-connect-access` | S3 read/write on that one bucket + `ses:SendEmail`/`SendRawEmail` |
| Instance profile `campus-connect-profile` | Binds the role to EC2 |
| User `campus-connect-ses-smtp` | SES SMTP credentials only (`ses:SendRawEmail`) |

The EC2 role is scoped to the single bucket by ARN, not `s3:*`. The SES SMTP
user exists separately because SMTP auth needs a static credential pair that
GoTrue can hold — that is the one place a long-lived key was unavoidable, so it
has exactly one permission.

### Mail (SES)
| Resource | Value |
|---|---|
| SMTP endpoint | `email-smtp.us-east-1.amazonaws.com:587` |
| SMTP username | `AKIA57DNKKIHUWV3JFYW` |
| Verified identity | `sumitmishramahadev@gmail.com` — **pending your click** |
| Configuration set | `campus-connect` (default for the identity) |
| SNS topic | `arn:aws:sns:us-east-1:960154456591:campus-connect-ses-events` |
| Suppression | Account-level, BOUNCE + COMPLAINT |
| Production access | **Requested and DENIED** — case `178617724700833` |

The SMTP password is not an IAM secret key; it is derived from one via an
HMAC-SHA256 chain. It is stored only in `/opt/campus-connect/stack/.env` on the
host.

---

## 4. The stack

Deployed from the official Supabase self-hosting sources at tag
**`self-hosted/v0.7.2`**, in `/opt/campus-connect/stack`.

| Service | Image |
|---|---|
| db | `supabase/postgres:17.6.1.136` |
| auth (GoTrue) | `supabase/gotrue:v2.189.0` |
| rest (PostgREST) | `postgrest/postgrest:v14.12` |
| realtime | `supabase/realtime:v2.102.3` |
| storage | `supabase/storage-api:v1.60.4` |
| imgproxy | `darthsim/imgproxy:v3.30.1` |
| kong | `kong/kong:3.9.3` |
| meta | `supabase/postgres-meta:v0.96.6` |
| studio | `supabase/studio:2026.08.03-sha-022b374` |
| supavisor | `supabase/supavisor:2.9.5` |
| functions | `supabase/edge-runtime:v1.74.0` |
| caddy | `caddy:2` |

All have `restart: unless-stopped` and Docker is enabled at boot, so the stack
returns by itself after a reboot.

### Project-specific overrides

Vendor files are left untouched so upstream updates can still merge cleanly.
Everything project-specific lives in one added file,
`docker-compose.campus.yml`:

```
COMPOSE_FILE=docker-compose.yml:docker-compose.caddy.yml:docker-compose.campus.yml
```

It does two things:

**1. Storage points at real S3, not the bundled MinIO.** Upstream's
`docker-compose.s3.yml` runs MinIO in a container — objects would then live on
the same EBS volume they were supposed to be moved off. The override sets
`STORAGE_BACKEND=s3` against the real bucket, with credentials from the
instance role.

**2. Eight-digit OTP.** `AppConfig._projectOtpLength` is 8
([app_config.dart:36](lib/core/config/app_config.dart#L36)) and the OTP screen
renders exactly that many boxes. GoTrue defaults to 6. Left unset, every
sign-in would be impossible to complete — the screen would want 8 digits and
the mail would carry 6.

---

## 5. Database

All 13 migrations applied cleanly, in order, with `ON_ERROR_STOP`.

| Check | Result |
|---|---|
| Tables in `public` | 84 |
| Functions | 210 |
| RLS policies | 60 |
| `messages` partitions | 21 |
| Storage buckets | `avatars`, `campus-assets` (public); `chat-media`, `verification-docs` (private) |
| Realtime publication | `connections, conversations, events, messages, notifications, poll_options, polls` |
| Seed data | 22 programs, 42 tags, 1 university |
| Cron jobs | `cc-expire-presence` (every min), `cc-retention` (03:30), `cc-purge-profiles` (04:00) |

### One thing that would have silently broken

`0010_jobs_and_maintenance.sql` wraps its three `cron.schedule()` calls in
`if exists (select 1 from pg_extension where extname = 'pg_cron')` and falls
through to a `raise notice` otherwise. On a fresh self-hosted Postgres the
extension is available but **not created**, so the migration would have
reported success while scheduling nothing — presence would never expire,
retention would never run, and deleted profiles would never be purged.

`create extension if not exists pg_cron;` is therefore run **before** the
migrations. If you ever rebuild this database from scratch, do the same.

### Reference data and anon

`GET /rest/v1/programs` with the anon key returns `[]`. This is correct, not a
bug: migration `0008` grants `programs_read`, `tags_read` and
`universities_read` to `authenticated` only — *"readable by any signed-in
student, writable by none"*. The registration wizard reads them after OTP
verification, when the session is authenticated. Behaviour is identical to
hosted Supabase.

---

## 6. Endpoints and access

**Base URL:** `https://13-223-251-151.sslip.io`

`sslip.io` resolves any `a-b-c-d.sslip.io` to `a.b.c.d`, which gave Let's
Encrypt a real hostname to issue against. The certificate is genuine and
browser-trusted (issuer `Let's Encrypt CN=YE2`, valid to 6 Nov 2026), so the
Flutter client accepts it on Android and iOS with no cleartext exemptions.

| Path | Goes to |
|---|---|
| `/auth/v1/*` | GoTrue |
| `/rest/v1/*` | PostgREST |
| `/realtime/v1/*` | Realtime (websocket upgrade verified, HTTP 101) |
| `/storage/v1/*` | Storage API |
| `/functions/v1/*` | Edge runtime |
| `/` | Studio, behind HTTP basic auth |

**Studio:** open the base URL in a browser. Username `supabase`; password is
`DASHBOARD_PASSWORD` in `/opt/campus-connect/stack/.env`.

**Secrets** are all in `/opt/campus-connect/stack/.env` on the host. Print them
with:
```bash
ssh -i ~/.ssh/campus-connect.pem ubuntu@13.223.251.151
cd /opt/campus-connect/stack && sh run.sh secrets
```
This file is the single copy of the JWT secret, service-role key and Postgres
password. **Back it up somewhere safe.** Losing it means losing the ability to
mint valid tokens for this deployment.

### Flutter

`dart_define.json` now reads:
```json
{
  "SUPABASE_URL": "https://13-223-251-151.sslip.io",
  "SUPABASE_ANON_KEY": "<anon key>",
  "OTP_LENGTH": "8"
}
```
Run as before:
```bash
flutter run --dart-define-from-file=dart_define.json
```

---

## 7. Operations

SSH (note the key path has no spaces on purpose):
```bash
ssh -i ~/.ssh/campus-connect.pem ubuntu@13.223.251.151
cd /opt/campus-connect/stack
```

| Task | Command |
|---|---|
| Status | `sh run.sh status` |
| Start | `sh run.sh start` |
| Stop | `sh run.sh stop` |
| Restart one service | `sh run.sh restart auth` |
| Logs | `sh run.sh logs auth` |
| Show secrets | `sh run.sh secrets` |
| Effective env of a service | `sh run.sh printenv storage` |
| Upgrade the stack | `sh update.sh` (3-way merges against `self-hosted/v0.7.2`) |

**psql:**
```bash
docker compose exec db psql -U postgres -d postgres
```

**Postgres from your laptop** (port is closed to the internet; tunnel instead):
```bash
ssh -i ~/.ssh/campus-connect.pem -L 5433:localhost:5432 ubuntu@13.223.251.151
# then connect to localhost:5433 with the POSTGRES_PASSWORD from .env
```

**Backup:**
```bash
docker compose exec -T db pg_dump -U postgres -Fc postgres > cc-$(date +%F).dump
```
There is **no automated backup yet** — see §9.

---

## 8. Swapping in your real domain

Everything was built so this is a three-step change. When you have the domain
(say `campusconnect.in`):

**1. Point DNS at the Elastic IP.** An `A` record for the host you want
(apex, or `api.campusconnect.in`) → `13.223.251.151`. If you want Route 53 to
run DNS, create the zone and move the nameservers at your registrar:
```bash
aws route53 create-hosted-zone --name campusconnect.in --caller-reference cc-$(date +%s)
```

**2. Update four lines in `.env` and restart:**
```bash
ssh -i ~/.ssh/campus-connect.pem ubuntu@13.223.251.151
cd /opt/campus-connect/stack
sed -i \
  -e 's|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.campusconnect.in|' \
  -e 's|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.campusconnect.in/auth/v1|' \
  -e 's|^SITE_URL=.*|SITE_URL=https://api.campusconnect.in|' \
  -e 's|^PROXY_DOMAIN=.*|PROXY_DOMAIN=api.campusconnect.in|' \
  .env
sh run.sh restart
```
Caddy fetches a fresh Let's Encrypt certificate automatically. Wait for DNS to
resolve first, or ACME will fail and retry.

**3. Update `dart_define.json`** with the new `SUPABASE_URL` and rebuild the app.

Then, for mail, verify the **domain** in SES rather than a Gmail address — it
enables DKIM, materially improves deliverability, and strengthens the pending
production-access request:
```bash
aws sesv2 create-email-identity --email-identity campusconnect.in
aws sesv2 get-email-identity --email-identity campusconnect.in \
  --query 'DkimAttributes.Tokens'   # add the 3 CNAMEs at your DNS host
```
Then set `SMTP_ADMIN_EMAIL=noreply@campusconnect.in` in `.env` and restart
`auth`.

> Existing user sessions carry a JWT whose `iss` is the old URL. Changing
> `API_EXTERNAL_URL` changes the issuer, so tokens minted before the switch
> stop validating and those users must sign in again. Do this before you have
> real students, or accept a one-time forced re-login.

---

## 9. What is done, what is not

### Verified working
- All 12 containers healthy; survive reboot
- Valid Let's Encrypt TLS
- All 13 migrations applied; 84 tables, 60 policies, 3 cron jobs live
- REST, Auth and Storage endpoints respond over HTTPS
- Realtime websocket upgrade (HTTP 101)
- **Storage round trip through to real S3** — uploaded a PNG via the Storage
  API, confirmed the object in the bucket (AES256, correct MIME), read it back
  byte-identical, deleted it
- Storage container obtains AWS credentials from the instance role — no AWS
  keys on the box
- `flutter analyze` clean, 263/263 tests pass
- **The Flutter app itself talks to this backend.** Ran on an Android emulator:
  `Supabase init completed` in the app log, and GoTrue recorded
  `user_agent: Dart/3.12 (dart:io)` → `POST /otp` → `200`. The OTP screen
  rendered **8 boxes**, confirming the `GOTRUE_MAILER_OTP_LENGTH=8` override
  reaches the client.
- **Full auth loop:** `POST /auth/v1/verify` with a valid OTP returned `200`
  with an ES256 `access_token`, a `refresh_token`, and the user record for
  `21bcs5084@cuchd.in` with `role: authenticated` and `email_confirmed_at` set.
- SES SMTP credentials authenticate (EHLO → STARTTLS → AUTH all OK)

### Blocked on you
1. **Click the SES verification link** sent to `sumitmishramahadev@gmail.com`.
   Until then GoTrue accepts a sign-in request but SES rejects the send, so
   **no OTP mail goes out**. This is the one thing standing between the current
   state and a working end-to-end login for you.
2. **Confirm the SNS subscription** (second email, same address) to receive
   bounce/complaint notifications.
3. **Give me the domain** when you have it — §8. It also unblocks the SES
   re-application.

The use-case text submitted to SES is kept at `ses-usecase.txt` so the
re-application can reuse it verbatim.

### Not done yet
| Gap | Impact | Effort |
|---|---|---|
| **No automated backups** | Instance loss = total data loss. Postgres lives on one EBS volume with no snapshot schedule. | Low — AWS Backup plan or a nightly `pg_dump` to S3 |
| **SES still in sandbox — request DENIED** | Only verified addresses receive mail. No real student can sign in. See below. | Re-apply after the domain exists |
| **Single point of failure** | One instance, one AZ. A host failure takes everything down. | Medium |
| **No monitoring/alerting** | Nothing tells you if a container dies or the disk fills. | Low — CloudWatch agent + alarms |
| **No log retention** | `docker compose logs` only; nothing shipped anywhere. | Low |
| **Certificate depends on sslip.io** | Fine today, but sslip.io is a third-party service. A real domain removes the dependency. | Low, once you have the domain |

**Recommended next:** automated backups. It is the cheapest item on that list
and the only one whose absence is unrecoverable.

### You cannot send mail *as* `@cuchd.in` — ever

This is the most important operational finding, and it is not a configuration
bug. The university's DNS says:

```
cuchd.in  SPF    "v=spf1 include:spf.protection.outlook.com -all"
cuchd.in  DMARC  "v=DMARC1; p=reject; pct=100; ..."
cuchd.in  MX     cuchd-in.mail.protection.outlook.com     (Microsoft 365)
```

- `-all` is a **hard fail**: only Microsoft's servers may send as `@cuchd.in`.
  Amazon SES is not on that list and cannot be added — the record belongs to
  the university.
- `p=reject` tells receivers to **discard** non-aligned mail outright. Not
  spam-folder — dropped.

So a message with `From: 21bcs5084@cuchd.in` relayed through SES fails SPF,
fails DKIM alignment (SES signs as `amazonses.com`), and DMARC then rejects it.
This was observed live: GoTrue reported `status 200`, SES accepted the message,
SES recorded **0 bounces** — and nothing ever arrived, because the rejection
happens at the receiving end after SES considers its job done.

**Consequence for launch:** the OTP sender must be an address on a domain *you*
control, with SPF and DKIM published for SES. `noreply@<your-domain>` sending
*to* `student@cuchd.in` is completely fine — receiving at cuchd.in was never the
problem. Only the From address was.

This makes the domain a hard prerequisite for real users, not a cosmetic
improvement. Until it exists, use the admin-API workaround below.

### Getting an OTP without mail (development only)

While mail is undeliverable, GoTrue's admin API mints the code directly and
returns it in the response without sending anything:

```bash
cd /opt/campus-connect/stack
SR=$(grep '^SERVICE_ROLE_KEY=' .env | cut -d= -f2-)
curl -sS -X POST "https://13-223-251-151.sslip.io/auth/v1/admin/generate_link" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" -H "Content-Type: application/json" \
  -d '{"type":"magiclink","email":"21bcs5084@cuchd.in"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["email_otp"])'
```

Type that code into the app's OTP screen. Requires the service-role key, so it
is a developer tool only — never expose this path to clients.

### The SES denial

The production-access request was submitted on 8 Aug 2026 and **denied**
(case `178617724700833`). The denial reason is readable in the SES console
under *Account dashboard*, or in Support Center — the Support API needs a paid
plan, so it cannot be fetched from the CLI here.

Almost certainly the cause is the website URL: the request had to give
`https://13-223-251-151.sslip.io`, an IP-derived hostname, because no domain
existed yet. Reviewers treat that as an unverifiable business. The Gmail sender
address does not help either.

A denial is **not** final — `put-account-details` can be called again, and the
same request from a real domain with DKIM configured is routinely approved. The
sequence that works:

1. Register the domain and point it at the Elastic IP (§8)
2. Verify it as an SES **domain** identity and add the three DKIM CNAMEs
3. Move the sender to `noreply@<your-domain>`
4. Re-submit, with the real domain as the website URL:
   ```bash
   aws sesv2 put-account-details --mail-type TRANSACTIONAL \
     --website-url "https://<your-domain>" \
     --use-case-description "$(cat ses-usecase.txt)" \
     --additional-contact-email-addresses sumitmishramahadev@gmail.com \
     --contact-language EN --production-access-enabled
   ```

Until then the account is capped at 200 messages/day to **verified addresses
only** — enough to develop and demo against, not enough to onboard students.

---

## 10. Cost

| Item | Monthly (USD) |
|---|---|
| t3.medium, on-demand, 730 h | ~$30.37 |
| 100 GB gp3 EBS | ~$8.00 |
| Public IPv4 address | ~$3.65 |
| S3 storage | ~$0.02 per GB stored |
| SES | $0.10 per 1,000 emails |
| SNS, Route 53 queries | pennies |
| **Baseline** | **~$42/month** |

Data transfer out is free to 100 GB/month, then $0.09/GB.

Reserved instances or a Savings Plan would cut the EC2 line by roughly 30–40%
if you commit to a year. Worth doing once the deployment is settled — not
before, in case the instance size changes.

---

## 11. Security notes

- SSH is restricted to a single IP; password auth is off (key-only, ed25519)
- Postgres is not reachable from the internet
- IMDSv2 is required — the SSRF-to-credentials path is closed
- EBS volume encrypted at rest; S3 objects encrypted with SSE-S3
- S3 bucket blocks all public access
- IAM is least-privilege: the instance role can touch one bucket and send mail,
  nothing else
- Studio is behind HTTP basic auth over TLS
- `.env` on the host holds every secret and is the thing to protect
- The **anon key is public by design** — it is safe in the client because RLS
  is what actually enforces access, and migration `0008` puts RLS on every
  table. The **service-role key bypasses RLS entirely** and must never reach
  the app or a repository.

### Still worth doing
- Rotate the SES SMTP credential once production access is granted
- Consider moving SSH behind SSM Session Manager and closing port 22 entirely
- The `dart_define.json` and `.env` files are gitignored — keep it that way

---

## 12. Note on version control

This document, and the whole deployment it describes, sits in a repository
where — per `FLUTTER_PROJECT_AUDIT_REPORT.md` — roughly **55% of the code has
never been committed**, including all of `supabase/` and all of `test/`. The
infrastructure is now reproducible from this file, but the schema it depends on
is not yet protected by version control.

Commit before anything else.

---

*Every claim in this document was verified by executing the check, not by
inspection. Resource IDs, image tags, row counts and test results are copied
from actual command output.*
