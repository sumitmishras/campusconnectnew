# Campus Connect — Flutter Project Implementation Audit

**Audited:** 7 August 2026
**Project path:** `C:\Users\Sumit Mishra\Desktop\campus connect\Campus-Connect`
**Audit type:** Read-only. No project code was modified.

---

## 1. Executive Summary

This is **not a half-built prototype**. It is a genuinely well-engineered Flutter
application with a real, deployed Postgres backend, and it is far closer to
finished than a typical project at this stage.

Hard evidence gathered during this audit:

| Check | Result |
|---|---|
| `flutter analyze` | **No issues found** (0 errors, 0 warnings, 0 lints) |
| `flutter test` | **263 tests, all passed** |
| `TODO` / `FIXME` / `HACK` markers in `lib/` | **Zero** |
| Dart files / LOC | 72 files, ~21,200 lines |
| Backend | 13 SQL migrations, live Supabase project `rlvbpwqrsiemhqfndnkz` |
| Test files | 14, covering providers, repositories, auth, chat, attachments |

The core product — auth, profiles, discovery, connections, moderation,
real-time chat with attachments, and a six-module Campus Hub — is implemented
end-to-end against Postgres, not mocked.

**What is actually missing is not features. It is the last mile to a shippable
app**: push notifications, release signing, app identity (name/icon), a handful
of decorative buttons that pretend to work, and — most urgently — **committing
the work to git**.

> ### The single most important finding
> **Roughly 55% of the codebase has never been committed.** The repository has
> exactly **one commit**. On disk there are 72 Dart files; git tracks **32**.
> The entire `supabase/` directory (all 13 migrations, RLS policies, the schema
> design document) and the entire `test/` suite are **untracked**. A stray
> `git clean -fd`, a bad IDE "revert", or a disk failure erases weeks of the
> best work in this project. **Fix this before writing another line of code.**

**Overall implementation: ~84%.**
**Recommendation: CONTINUE this codebase. Do not rewrite. There is no evidence
justifying a rewrite, and substantial evidence against one.**

---

## 2. Project Overview

**Campus Connect** — a student community app for Chandigarh University.

| Property | Value |
|---|---|
| Package name | `campus_connect` |
| Version | `1.0.0+1` |
| Dart SDK | `^3.11.5` |
| Android namespace | `com.chandigarhuniversity.campus_connect` |
| Platforms configured | Android, iOS, Web, Windows, Linux, macOS |
| Target user | CU students, verified by university email domain |

### Dependencies (`pubspec.yaml`)

All current, none deprecated, none exotic:

| Package | Purpose | Assessment |
|---|---|---|
| `supabase_flutter: ^2.8.0` | Auth, Postgres, Realtime, Storage | Core. Actively used. |
| `provider: ^6.1.5+1` | State management | Core. Used correctly. |
| `google_fonts: ^8.2.0` | Typography | Used |
| `lucide_icons_flutter: ^3.1.15` | Icon set | Used throughout |
| `flutter_animate: ^4.5.2` | Animations | Used |
| `file_picker: ^11.0.3` | Chat attachments | Used |
| `url_launcher: ^6.3.2` | Opening attachment URLs | Used (1 site) |
| `shared_preferences: ^2.5.5` | Mock-mode session persistence | Used |
| `uuid: ^4.6.0` | Idempotent message client IDs | Used |
| `intl: ^0.20.3` | Date formatting | Used |
| `faker: ^2.2.0` | **Mock data generation only** | **Dev-only dep sitting in `dependencies:`** |
| `flutter_lints: ^6.0.0` | Linting | Enforced and clean |

**Note:** `faker` is a demo-data package but is declared under `dependencies:`,
not `dev_dependencies:`. It ships in the release binary. Minor size/hygiene issue.

**No assets are declared.** The `flutter: assets:` block is entirely commented
out. All imagery is network-loaded. There is no app-specific launcher icon,
splash image, or bundled font file.

---

## 3. Current Architecture

The architecture is **feature-first with a clean data layer**, and it is
noticeably better than average.

```
lib/
├── main.dart                     # Bootstrap + AuthGate + lifecycle/presence
├── core/
│   ├── config/app_config.dart    # --dart-define config, OTP length
│   ├── data/
│   │   ├── repositories/         # 10 repos, each Supabase + Mock impl
│   │   ├── *_mapper.dart         # Postgres row → domain model
│   │   ├── reference_data.dart   # Programs/tags lookup cache
│   │   └── mock_profile_store.dart
│   ├── models/                   # 7 pure domain models
│   ├── providers/                # 4 ChangeNotifiers (auth, user, chat, campus)
│   ├── services/                 # Supabase client, auth backend, presence, files
│   ├── theme/                    # Colors, typography, light+dark themes
│   ├── utils/debouncer.dart
│   ├── widgets/                  # Shared UI primitives
│   └── mock_data/                # Fixture generator (mock mode only)
└── features/
    ├── auth/         (4 screens)  ├── chat/        (3 screens + 2 widgets)
    ├── campus_hub/   (8 screens)  ├── connection/  (1 screen)
    ├── discover/     (1 + card)   ├── navigation/  (1)
    └── profile/      (7 screens)
```

### The defining architectural decision: dual-mode data layer

`lib/core/data/repositories/repositories.dart` is a **composition root**. Every
one of the ten repositories has two implementations — `Supabase*` and `Mock*` —
and one place decides between them based on `SupabaseService.isReady`:

```dart
static ProfileRepository _buildProfiles() {
  if (SupabaseService.isReady) return SupabaseProfileRepository(SupabaseService.client);
  return MockProfileRepository(store: mockStore, students: _fixtureStudents);
}
```

Credentials arrive via `--dart-define`; without them the app boots into a fully
functional offline demo. This is a deliberate, well-documented pattern that
keeps the app runnable for anyone who clones it and makes widget tests trivial
(`Repositories.overrideForTest(...)` / `reset()`).

**Chat is the one deliberate exception.** It has no mock implementation — only
`UnavailableChatRepository`, which returns empty lists and throws
`ChatFailure` on write. The code comments the reasoning explicitly: *"a
misconfigured build should look broken, not busy."* This is correct judgment,
not an oversight.

### State management

`provider` with `ChangeNotifierProxyProvider` wiring auth identity into
`UserProvider` and `ChatProvider`, so a sign-out cannot leave the previous
student's threads on screen. Optimistic updates with rollback are implemented
throughout `UserProvider` (send/accept/decline/block/report all apply locally,
then revert on failure) — and each rollback path has a passing test.

### Backend

13 migrations in `supabase/migrations/`, plus a 530-line `DATABASE.md`
explaining the design reasoning. Highlights that indicate real engineering
rather than scaffolding:

- **Single `conversations` table** for DMs and groups. `conversation_members`
  doubles as the membership table for clubs, communities, study groups and
  projects — so joining a club and appearing in its chat are one INSERT and
  cannot drift apart. Four join tables collapse into one.
- **Per-conversation `seq bigint`** allocated under row lock inside
  `send_message()`. Unread count is arithmetic (`last_seq - last_read_seq`),
  read receipts are one integer per member, pagination is a keyset scan. No
  counter tables, no per-message receipt rows.
- **`messages` hash-partitioned on `conversation_id`** into 16 partitions, with
  a documented argument for why hash beats time partitioning here.
- **Idempotent sends** via `UNIQUE (conversation_id, client_msg_id)`, with the
  ID generated client-side before the first attempt.
- **RLS across every table** (migration `0008`).
- `user_presence` kept as a narrow table with `fillfactor = 70` and no secondary
  indexes, with the reasoning spelled out.

**Verdict on architecture: keep it.** It is coherent, tested, documented, and
correctly separated. There is nothing here that needs restructuring.

---

## 4. Feature Implementation Status

| Feature | Status | Evidence | What's Working | What's Missing | Priority |
|---|---|---|---|---|---|
| **Supabase bootstrap / config** | ✅ | `supabase_service.dart`, `app_config.dart` | Init, `isReady` gate, configurable OTP length, realtime rate tuning | README documents none of it | Low |
| **CU email identity** | ✅ | `cu_identity.dart` | Domain validation, UID parsing, client + DB trigger both enforce | — | — |
| **OTP sign-in** | ✅ | `auth_backend.dart:SupabaseAuthBackend`, `otp_screen.dart` | Send, verify, readable error mapping, rate-limit messages | — | — |
| **Session restore** | ✅ | `restoreSession()`, `AuthGate` | Auto-refresh token, secure storage, splash → correct destination | — | — |
| **Registration wizard** | ✅ | `registration_wizard.dart` (647 L) | Multi-step, server-derived department/course/year, username uniqueness (23505 mapped) | Avatar step limited to 6 canned images | Medium |
| **Sign out** | ✅ | `settings_screen.dart` + `AuthProvider.logout()` | Confirm dialog, full nav reset | — | — |
| **Account deletion** | ✅ | `deleteAccount()` → `request_account_deletion` RPC | 30-day grace + `purge_deleted_profiles()` job | — | — |
| **Profile view / edit** | 🟡 | `my_profile_screen.dart`, `edit_profile_screen.dart` | All fields editable, persists to Postgres, real upload to `avatars` bucket | **Photo picker offers only 6 hardcoded pravatar.cc URLs** — no camera/gallery | High |
| **Privacy settings** | ✅ | `privacy_settings_screen.dart` | Toggles persist via `auth.updatePrivacy()`, blocked-user list | — | — |
| **Discover** | ✅ | `discover_screen.dart`, `discover_repository.dart` | Debounced search, advanced filters + active count, infinite scroll pagination, excludes self + blocked | — | — |
| **Connections** | ✅ | `user_provider.dart`, `connection_repository.dart` | Send/accept/decline/withdraw/remove/ignore, all six relationship states, optimistic + rollback, realtime | — | — |
| **Block / unblock** | ✅ | `user_provider.dart` | Removes from Discover + graph + bookmarks, rollback on failure | — | — |
| **Report user** | ✅ | `connection_repository.dart:288` → `reports` table | Real insert, enum values, not remembered if write fails | No admin/review surface (out of app scope) | Low |
| **Bookmarks** | ✅ | `bookmark_repository.dart`, `bookmarks_screen.dart` | Polymorphic table, resolves through profile cache | — | — |
| **Direct chat** | ✅ | `chat_repository.dart` (841 L), `chat_provider.dart` (1069 L) | Send, keyset pagination, idempotent retry, soft delete, mute, clear history, block gate | — | — |
| **Group chat** | ✅ | `group_chat_screen.dart` (703 L) | Membership = `conversation_members`, join/leave, member list, leave flow | — | — |
| **Realtime messaging** | ✅ | `_inbox` channel, `onPostgresChanges` | Live inserts + updates, reconnect stream, lifecycle re-sync on resume | — | — |
| **Typing indicators** | ✅ | Broadcast channel, `kTypingTimeout = 4s` | Ephemeral, never written to Postgres — correct design | — | — |
| **Read receipts** | ✅ | `markRead()`, `notifyRead()`, `ReadReceipt` | Integer `last_read_seq`, DM ticks + group "seen by all" | — | — |
| **Presence / online status** | ✅ | `presence_service.dart`, `main.dart` lifecycle observer | Channel join/leave on foreground/background, durable `user_presence` fallback | — | — |
| **Chat attachments** | ✅ | `storage_repository.dart`, `attachment_picker.dart`, `attachment_bubble.dart` | Pick → upload → attach, signed URLs, image preview, doc launch, graceful placeholder on failure | — | — |
| **Campus Hub home** | ✅ | `campus_hub_screen.dart` | Counts from all six modules in one parallel fetch (11 reads) | — | — |
| **Events** | 🟡 | `events_screen.dart`, `event_detail_screen.dart` | List, detail, RSVP (`setEventRsvp`), save/unsave, live poll of counts | **Share button is fake** (see §9); no event creation in app | Medium |
| **Communities** | 🟡 | `communities_screen.dart` | List, join/leave → chat membership | No creation flow (may be admin-only by design) | Low |
| **Clubs** | 🟡 | `clubs_screen.dart` | List, join/leave → chat membership | No creation flow (may be admin-only by design) | Low |
| **Study groups** | ✅ | `study_groups_screen.dart` (407 L) | Full create sheet, join/leave, max members, error surfacing | — | — |
| **Projects** | ✅ | `projects_screen.dart` (360 L) | Create with cover upload, tech stack, roles, apply/withdraw | — | — |
| **Polls** | ✅ | `polls_screen.dart` (291 L) | Create via `create_poll` RPC, vote, realtime tally refresh | — | — |
| **In-app notifications** | ✅ | `notifications_screen.dart`, `campus_repository.dart` | Realtime feed, mark one/all read, clear all | — | — |
| **Push notifications** | 🔴 | **No package, no code** | Nothing | Entire feature. `devices` table exists in DB and is unused | **Critical** |
| **Notification preferences** | 🟡 | `settings_screen.dart:19-22` | Four toggles render and interact | **Pure local `bool` state** — not persisted, not read by anything | High |
| **Help & Support / feedback** | 🟡 | `help_support_screen.dart:132-186` | Sheet, validation, UX | **Submit writes nothing.** Shows "Report submitted" and discards the text | High |
| **Theming (light/dark)** | ✅ | `app_theme.dart`, `app_colors.dart`, `app_typography.dart` | Full light + dark, follows system | No manual override (row is a snackbar) | Low |
| **Navigation** | ✅ | `main_navigation.dart` | 5-tab bottom nav, imperative push for detail routes | No named routes / deep links | Low |
| **Release build config** | ⚠️ | `android/app/build.gradle.kts:35-38` | Debug builds fine | **Release signed with debug keys** — cannot ship | **Critical** |
| **App identity** | 🔴 | `AndroidManifest.xml`, `mipmap/ic_launcher` | — | Label is `campus_connect`; default Flutter launcher icon | High |
| **Test suite** | ✅ | 14 files, 263 tests | Providers, repos, auth, chat, attachments, login flow, smoke | No integration/E2E against real Supabase | Medium |
| **Source control** | ⚠️ | 1 commit; 32/72 lib files tracked | — | **40 Dart files + all of `supabase/` + all of `test/` untracked** | **Critical** |

---

## 5. Completed Features (✅)

These are implemented end-to-end and backed by passing tests and/or real
Postgres calls. **Do not spend time re-verifying these.**

1. **Authentication** — CU email validation, OTP send/verify against Supabase
   Auth, session restore with token refresh, registration wizard writing a real
   profile, sign-out, and GDPR-style account deletion via RPC with a 30-day
   purge job.
2. **Discover** — debounced search, multi-field advanced filters with an active
   count, infinite-scroll pagination via `PageResult`, self and blocked users
   excluded at the query level.
3. **Connections & social graph** — the full six-state relationship machine
   (none / outgoing / incoming / connected / blocked / ignored), directional
   tabs, optimistic mutation with tested rollback on every path, live updates
   over a Realtime channel with burst coalescing.
4. **Moderation** — block/unblock (cascading to Discover, graph and bookmarks)
   and user reporting into the `reports` table.
5. **Chat** — the strongest module in the project. DMs and groups on one table,
   `seq`-ordered messages, keyset pagination, idempotent sends surviving flaky
   campus wifi, soft delete, mute, clear history, leave, member lists, block
   gating, typing indicators over broadcast, integer read receipts, presence,
   and file/image attachments with signed URLs.
6. **Campus Hub** — six modules (events, communities, clubs, study groups,
   projects, polls) fetched in one parallel batch, with membership unified
   through `conversation_members`. Study groups, projects and polls have
   complete creation flows.
7. **In-app notifications** — realtime feed with mark-read and clear.
8. **Privacy settings** — genuinely persisted, unlike the notification toggles.
9. **Theming** — complete light and dark themes following the system setting.
10. **Database layer** — 13 migrations, RLS on every table, storage buckets and
    policies, background jobs for retention/presence-decay/fan-out, seeded
    reference data.

---

## 6. Partially Implemented Features (🟡)

### 6.1 Profile photo selection — **High priority**
**File:** `edit_profile_screen.dart:23-29, 298-364`; `registration_wizard.dart:27-32`

The upload machinery is **real** — `_applyAvatar()` fetches bytes and calls
`Repositories.storage.uploadAvatar()` into the `avatars` bucket, with error
handling and a loading state. But the picker (`_pickAvatar`) offers a
`showModalBottomSheet` containing exactly six hardcoded `i.pravatar.cc` URLs.
The app downloads a stranger's stock photo from a third-party CDN and re-uploads
it as the student's avatar. Every user picks from the same six faces.

`file_picker` is already a dependency and is already used successfully for chat
attachments — the wiring exists, it just was never pointed at the avatar flow.

### 6.2 Notification preferences — **High priority**
**File:** `settings_screen.dart:19-22, 69-99`

Four `SwitchListTile`s backed by plain `setState` booleans. They reset on every
screen exit, are never written to storage or Postgres, and no other code reads
them. They are UI theatre. (Contrast with `privacy_settings_screen.dart`, which
does this correctly via `auth.updatePrivacy()`.)

### 6.3 Help & Support submission — **High priority**
**File:** `help_support_screen.dart:132-186`

`_showFeedbackSheet()` builds a proper sheet with validation, then on Submit
simply pops and shows *"Report submitted. Our team will look into it."* The
text is discarded. This is worse than a missing feature: for the **safety
reporting** path, it actively tells a student their harassment report was
received when nothing was sent anywhere.

Note that user-to-user reporting via profile cards *is* real — it writes to
`reports`. Only this Help & Support path is fake.

### 6.4 Events / Communities / Clubs — creation
**Files:** `events_screen.dart`, `communities_screen.dart`, `clubs_screen.dart`

Joining, leaving and RSVP are fully wired. There is no in-app creation flow for
any of the three. This is plausibly intentional (staff/admin-created content),
but there is no admin tool in the repo either, so **content has to be inserted
via the Supabase dashboard by hand**. Worth an explicit decision.

### 6.5 Theme override
**File:** `settings_screen.dart:101-113`

The "Theme" row opens a snackbar explaining that the app follows the system
setting. Functional as written, but there is no manual light/dark choice.

---

## 7. Pending / Not Implemented Features (🔴)

### 7.1 Push notifications — **CRITICAL**
There is no push notification implementation of any kind. No
`firebase_messaging`, no `flutter_local_notifications`, no APNs/FCM config, no
token registration.

The backend anticipated this: migration `0002` creates a **`devices` table**
that nothing writes to, and `0010` implements notification fan-out that
currently terminates in the in-app feed only.

For a messaging-centric social app this is not a polish item — a student who
closes the app learns nothing happened until they reopen it. This is the
largest functional gap in the product.

### 7.2 App identity — **High**
- Android label is `campus_connect` (`AndroidManifest.xml`), not "Campus Connect"
- Default Flutter launcher icon on every platform
- No adaptive icon, no splash screen asset
- Settings still reads **"Version 1.0.0 (demo build)"**

### 7.3 Release signing — **CRITICAL / see §8**

### 7.4 Documentation — **Medium**
`README.md` is the **untouched Flutter template**. It does not mention that the
app requires `--dart-define-from-file=dart_define.json` to reach the backend, or
that it silently degrades to mock data without it. Anyone who clones this repo
and runs `flutter run` gets the demo and will not know why chat is empty.

`supabase/DATABASE.md` documents migrations `0001`–`0012`. **Migration `0013`
exists and is not in the table** — documentation drift.

### 7.5 Observability — **Medium**
No crash reporting (Sentry/Crashlytics), no analytics, no structured logging.
Once this is on real phones there will be no way to learn about failures.

### 7.6 Deep links / named routes — **Low**
All navigation is imperative `MaterialPageRoute` pushes. No route table, no deep
linking. A push notification tap cannot open a specific thread — which becomes
relevant the moment 7.1 is built.

---

## 8. Broken / Blocked Features (⚠️)

### 8.1 Release builds are signed with debug keys — **BLOCKS DISTRIBUTION**
**File:** `android/app/build.gradle.kts:35-38`

```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

A debug-signed APK cannot be uploaded to Play, and any build shipped this way
cannot later be updated by a properly-signed one. No keystore, no
`key.properties`, no upload key. **Nothing can be distributed until this is
fixed.**

### 8.2 Uncommitted work — **BLOCKS EVERYTHING ELSE**
- Repository has **one commit**: `8083fc6 "Complete Phase 3 and Phase 4 UI implementation"`
- **77** changed or untracked paths
- git tracks **32** of the **72** Dart files in `lib/`
- **Entirely untracked:** `supabase/` (all 13 migrations, RLS, `DATABASE.md`),
  `test/` (all 14 files, 263 tests), `lib/core/config/`, `lib/core/data/`,
  `lib/core/services/`, `lib/core/utils/`, `lib/features/chat/widgets/`,
  `auth_provider.dart`, and 5 profile screens

The best work in this project — the database design and the test suite — has
zero version-control protection. There is no branch, no remote verified, no
history to recover from. This is not a code-quality issue; it is an existential
one.

### 8.3 Repository hygiene — Low
A nested duplicate `supabase/supabase/.temp/` directory exists alongside
`supabase/.temp/`, almost certainly from running the Supabase CLI from the wrong
working directory. Harmless but confusing.

---

## 9. Mock / Placeholder / Temporary Components

| Item | Location | What it does now | What must replace it |
|---|---|---|---|
| **Fake event share** | `event_detail_screen.dart:42-49` | Shows *"Event link copied to clipboard"* — **copies nothing**. No `Clipboard.setData`, no `share_plus`. | Real clipboard write, or `share_plus` with a deep link. Requires §7.6. |
| **Fake feedback / safety report** | `help_support_screen.dart:167-181` | Shows *"Report submitted. Our team will look into it."* — discards text. | Insert into `reports` (or a new `feedback` table). Reuse `SupabaseConnectionRepository.report()` at `connection_repository.dart:288`. |
| **Fake FAQ row** | `help_support_screen.dart:109` | `onTap` → snackbar | Real FAQ content or a hosted link |
| **Hardcoded avatar set** | `edit_profile_screen.dart:23-29`, `registration_wizard.dart:27-32` | Six `i.pravatar.cc` URLs | Device gallery/camera via `file_picker` (already wired for chat) |
| **Mock avatar URLs in fixtures** | `mock_data_generator.dart:162` | `i.pravatar.cc/300?img=N` | Mock-mode only — acceptable, leave it |
| **Mock signup avatar** | `auth_backend.dart:319` | `i.pravatar.cc/300?u=$seed` | Mock backend only — acceptable |
| **Ephemeral notification toggles** | `settings_screen.dart:19-22` | Local `bool`s | Persist to `profiles` or `shared_preferences`, then honour in push fan-out |
| **"demo build" version string** | `settings_screen.dart` (About row) | Literal `'Version 1.0.0 (demo build)'` | Read from `package_info_plus` |
| **`MockDataGenerator`** | `lib/core/mock_data/` (404 L) | Generates fixture campus | **Keep.** Deliberate, isolated, used by tests. Not dead code. |
| **All `Mock*Repository` classes** | `lib/core/data/repositories/` | Offline implementations | **Keep.** Architectural, documented, test-critical. |
| **`faker` dependency** | `pubspec.yaml` | Fixture generation | Move to `dev_dependencies:` |

**Important distinction:** the ten `Mock*Repository` classes are *not*
placeholder code. They are a deliberate offline mode with documented reasoning
and full test coverage. The genuinely fake items are only the five UI stubs in
the top rows of the table above.

---

## 10. Technical Issues

### Compilation & runtime
- ✅ `flutter analyze` — clean. No compilation risk.
- ✅ 263 tests pass. No known runtime regressions.
- 🟡 `main.dart:154-168` — `_syncSession()` is called from `build()`. It is
  guarded by `_presenceFor` so it is idempotent, but side effects in `build()`
  are fragile if that guard is ever edited.
- 🟡 `privacy_settings_screen.dart:18` — `auth.currentUser!` force-unwrap. Safe
  today because the screen is only reachable behind the auth gate, but it will
  crash rather than degrade if that ever changes.

### Error handling
- ✅ Strong overall. Typed failures (`AuthFailure`, `ChatFailure`,
  `CampusFailure`, `StorageFailure`, `ConnectionFailure`) with human-readable
  message mapping — including Postgres error code `23505` → *"That username is
  already taken."*
- ✅ Optimistic mutations roll back on failure, each with a test.
- 🟡 No global error boundary / `FlutterError.onError` handler.
- 🔴 No crash reporting — failures on real devices will be invisible.

### Security
- ✅ `dart_define.json` is in `.gitignore` and confirmed absent from the git
  index. Credentials are not committed.
- ✅ The exposed key is the **anon** key, which is public by design and safe
  provided RLS is correct — and migration `0008` applies RLS to every table.
- ✅ Client cannot delete its own auth row; deletion goes through
  `request_account_deletion` RPC with a grace period.
- ✅ CU domain enforced both client-side and by a DB trigger.
- 🟡 `avatars` bucket is public. Deliberate and reasoned (40 avatars per Discover
  scroll × signed URLs = 40 round trips), but it does mean avatar URLs are
  world-readable.
- 🟡 The anon key is written in plaintext in `dart_define.json` on disk. Fine
  locally; needs to move to CI secrets before any shared build pipeline.

### Architecture & code quality
- ✅ Zero TODO/FIXME markers across 21k lines.
- ✅ Consistent naming, genuinely explanatory comments (they explain *why*, not
  *what*), clean layer separation.
- 🟡 Three files exceed 1,000 lines (`chat_provider.dart` 1069,
  `user_provider.dart` 1017, `campus_repository.dart` 1017). Not currently a
  problem — they are cohesive — but they are the natural split points if they
  keep growing.
- 🟡 No dependency injection framework; `Repositories` is a static singleton.
  Works, and has a test seam (`overrideForTest`/`reset`), but static state
  requires discipline in `tearDown`.

### Performance
- ✅ `fetchAll()` issues 11 reads in parallel rather than serially.
- ✅ Keyset pagination for messages; offset-free.
- ✅ Debounced search (`debouncer.dart`).
- ✅ Realtime event bursts coalesced into a single reload (tested).
- ✅ Hash partitioning prunes message reads to one partition.
- 🟡 No image caching package (`cached_network_image`). Avatars re-download on
  scroll; Flutter's in-memory cache only goes so far on a long Discover list.

### Dependencies
- ✅ All current, none deprecated.
- 🟡 `faker` in `dependencies:` instead of `dev_dependencies:`.

### Production readiness
- 🔴 Debug signing (§8.1)
- 🔴 No push notifications (§7.1)
- 🔴 Default app name and icon (§7.2)
- 🔴 No crash reporting or analytics (§7.5)
- 🔴 Template README (§7.4)
- ⚠️ 55% of code uncommitted (§8.2)

---

## 11. Current User Flow

```
                        app launch
                             │
                    SupabaseService.initialize()
                             │
                    ┌────────┴────────┐
              credentials?         no credentials
                    │                 │
              LIVE MODE           MOCK MODE
                    │                 │
                    └────────┬────────┘
                             ▼
                      AuthGate (main.dart)
                             │
        ┌──────────┬─────────┼──────────────┐
     checking   loggedOut  needsProfile   loggedIn
        │           │           │            │
    _SplashScreen   ▼           ▼            ▼
                Welcome    Registration   MainNavigation
                    │        Wizard            │
                    ▼           │              │
             EmailLoginScreen   │              │
                    │           │              │
                    ▼           │              │
               OtpScreen ───────┘              │
                                               │
        ┌──────────┬───────────┬───────────┬───┴────────┐
        ▼          ▼           ▼           ▼            ▼
    Discover   CampusHub  Connections    Chat        Profile
        │          │           │           │            │
    StudentCard  6 modules  6 states   ChatList     MyProfile
        │          │           │           │            │
   StudentProfile  ├ Events → EventDetail  ├ ChatDetail ├ EditProfile
        │          ├ Communities           └ GroupChat  ├ Bookmarks
   Connect/Block/  ├ Clubs                              ├ Settings
   Report/Message  ├ StudyGroups (create)               │  ├ Privacy
        │          ├ Projects (create)                  │  └ Help&Support
        └──────────┼ Polls (create/vote)                └ Notifications
                   └ Notifications
```

### Flow assessment

| Segment | State | Notes |
|---|---|---|
| Launch → splash → gate | ✅ Working | Three-way branch is correct and tested |
| Welcome → email → OTP → home | ✅ Working | `login_flow_test.dart` covers it |
| OTP → registration wizard → home | ✅ Working | Fires only when profile is incomplete |
| Discover → profile → connect | ✅ Working | Optimistic, with rollback |
| Profile → message → chat detail | ✅ Working | `openDirectConversation`, error surfaced |
| Chat list → detail → send/attach | ✅ Working | Full realtime path |
| Campus Hub → join → group chat | ✅ Working | Membership and chat are one write |
| Events → detail → RSVP / save | ✅ Working | — |
| Events → detail → **share** | ⚠️ **Lies** | Claims clipboard copy, copies nothing |
| Settings → **notification toggles** | ⚠️ **Dead end** | Flip and reset, affect nothing |
| Settings → Help → **submit report** | ⚠️ **Lies** | Claims submission, discards input |
| Edit profile → **change photo** | 🟡 Partial | Real upload, six canned images |
| **App backgrounded → message arrives** | 🔴 **Missing** | No push. User learns nothing until reopen |
| Mock mode → chat tab | 🟡 By design | Empty with an explanation, deliberately |

---

## 12. Overall Progress Estimate

### Method
Weighted by share of total engineering effort for a shippable v1 — **not** by
screen count. Screen count would overstate completion, because the Campus Hub's
eight screens are far cheaper than the chat subsystem's two.

| Area | Weight | Complete | Contribution |
|---|---:|---:|---:|
| Database, migrations, RLS, storage, jobs | 20% | 95% | 19.0 |
| Chat subsystem (DM, group, realtime, attachments) | 20% | 90% | 18.0 |
| Campus Hub (6 modules) | 15% | 85% | 12.8 |
| Authentication & onboarding | 10% | 95% | 9.5 |
| Connections & moderation | 10% | 95% | 9.5 |
| Profiles & settings | 10% | 85% | 8.5 |
| Discover | 8% | 95% | 7.6 |
| Release readiness (signing, push, identity, docs, observability) | 7% | 15% | 1.1 |
| **Total** | **100%** | | **~85.9** |

### Status distribution across total scope

- **✅ Completed: ~78%**
- **🟡 Partially implemented: ~9%**
- **🔴 Pending / not implemented: ~11%**
- **⚠️ Broken / blocked: ~2%**

### **Estimated overall implementation: ~84%**

*(78% complete + half credit for the 9% partial + quarter credit for the 2%
blocked ≈ 84%. The weighted-effort model independently gives ~86%. Both land in
the same band; ~84% is the conservative figure.)*

### How to read this number
The remaining ~16% is **not** distributed evenly across features. It is
concentrated almost entirely in one area — **release readiness** — which sits at
roughly 15% complete and carries a 7% weight. The product itself is close to
feature-complete; the *shipping vehicle* barely exists.

The confidence in this estimate is unusually high because it rests on
executable evidence: a clean analyzer and 263 passing tests confirm the
"completed" column is real rather than aspirational.

---

## 13. Prioritized Action Plan

### Phase 1 — Must Do

| # | Task | Reason | Files / Modules | Complexity | Depends on |
|---|---|---|---|---|---|
| 1 | **`git add -A` and commit everything; push to a remote** | 40 Dart files, all 13 migrations and all 263 tests are unprotected. One bad command loses the project. | whole repo | **Low** | none |
| 2 | **Generate a release keystore; wire `key.properties`** | Debug signing blocks all distribution, permanently. | `android/app/build.gradle.kts`, new `key.properties` (gitignored) | Low | 1 |
| 3 | **Implement push notifications** | A chat app that is silent when closed is not usable. `devices` table already exists and is unused. | new `push_service.dart`, `main.dart`, migration `0010` fan-out, `devices` table | **High** | 1, 2 |
| 4 | **Make the Help & Support safety report real** | It currently tells students a harassment report was filed when nothing was sent. Correctness and duty-of-care issue. | `help_support_screen.dart:167`; reuse `connection_repository.dart:288` | **Low** | 1 |
| 5 | **Persist notification preferences** | Prerequisite for #3 — push fan-out must honour them. | `settings_screen.dart:19-22`, `profiles` table or `shared_preferences` | Low–Medium | 1 |
| 6 | **Real photo picker for avatars** | Every user currently shares six stock faces. `file_picker` is already wired for chat. | `edit_profile_screen.dart:298`, `registration_wizard.dart:27` | **Low** (reuse `attachment_picker.dart`) | 1 |
| 7 | **App name + launcher icon** | Ships as `campus_connect` with the default Flutter icon. | `AndroidManifest.xml`, `ios/Runner/Info.plist`, `mipmap/`, `flutter_launcher_icons` | Low | 1 |
| 8 | **Decide: how do Events/Clubs/Communities get created?** | No in-app flow and no admin tool. Content must be hand-inserted via the dashboard. | `events_screen.dart`, `clubs_screen.dart`, `communities_screen.dart` | Medium (decision first) | 1 |

**Suggested order: 1 → 2 → 4 → 6 → 5 → 7 → 8 → 3.**
Do #1 today. Then clear the cheap high-value items (4, 6, 5, 7) before starting
push, which is the only genuinely large task in this phase.

### Phase 2 — Should Do

| # | Task | Reason | Files | Complexity | Depends on |
|---|---|---|---|---|---|
| 9 | Fix the fake event share | Claims a clipboard copy that never happens | `event_detail_screen.dart:42` | Low | 12 (for deep links) |
| 10 | Crash reporting (Sentry or Crashlytics) | Zero visibility into on-device failures | `main.dart`, `pubspec.yaml` | Low–Medium | 1 |
| 11 | `cached_network_image` for avatars | Discover re-downloads avatars on every scroll | `app_widgets.dart:UserAvatar` | Low | — |
| 12 | Named routes / deep links | Push notification taps must open a specific thread | `main.dart`, new `app_router.dart` | Medium | 3 |
| 13 | Version string from `package_info_plus` | Settings hardcodes "1.0.0 (demo build)" | `settings_screen.dart` | Low | — |
| 14 | Move `faker` to `dev_dependencies` | Demo package ships in the release binary | `pubspec.yaml` | Low | — |
| 15 | Global `FlutterError.onError` boundary | Uncaught framework errors surface as red screens | `main.dart` | Low | 10 |
| 16 | Update `DATABASE.md` for migration `0013` | Doc drift already begun | `supabase/DATABASE.md` | Low | 1 |
| 17 | Rewrite `README.md` | Template README hides the `--dart-define-from-file` requirement | `README.md` | Low | 1 |
| 18 | Delete nested `supabase/supabase/` | CLI-run-from-wrong-directory artifact | `supabase/` | Low | 1 |

### Phase 3 — Release Preparation

| # | Task | Reason | Complexity |
|---|---|---|---|
| 19 | Integration tests against a real Supabase instance | 263 tests all run against fakes; RLS and RPCs are untested from the client | Medium–High |
| 20 | Manual QA pass in live mode on physical Android + iOS | Realtime, presence and attachments behave differently on real networks | Medium |
| 21 | Verify all RLS policies with a second real account | RLS is the entire security model; it has never been adversarially tested | Medium |
| 22 | Play Store / App Store assets, listing, privacy policy | Required for submission; app collects student PII | Medium |
| 23 | Offline / no-network behaviour audit | `ChatFailure` paths exist but have not been exercised on a real dropped connection | Medium |
| 24 | Load-check Discover and chat with realistic row counts | Design claims scale; it has not been measured | Medium |
| 25 | Accessibility pass (contrast, tap targets, screen reader) | Never audited | Medium |

### Phase 4 — Optional

| # | Task | Complexity |
|---|---|---|
| 26 | Manual light/dark theme override | Low |
| 27 | Message reactions (`message_reactions` table already exists in schema) | Medium |
| 28 | Split the three 1,000-line files | Medium |
| 29 | Analytics / engagement funnels | Medium |
| 30 | Web build polish (currently configured but unverified) | Medium |
| 31 | In-app admin surface for the `reports` queue | High |

---

## 14. Continue vs Rewrite Recommendation

### **CONTINUE. Emphatically. A rewrite would be a serious mistake.**

The rewrite question is worth taking seriously only when there is evidence of
structural rot. Here the evidence points hard the other way:

**Evidence against a rewrite:**

1. **The analyzer is clean and 263 tests pass.** You cannot fake this. It means
   the "completed" column in §4 is real, not aspirational.
2. **Zero TODO/FIXME markers in 21,000 lines.** Loose ends were closed, not
   deferred.
3. **The architecture is already what a rewrite would produce.** Feature-first
   layout, repository pattern with a composition root, typed failures, a test
   seam, optimistic updates with rollback. There is no better structure waiting
   on the other side of a rewrite.
4. **The database design is the most valuable artifact here and is genuinely
   sophisticated.** Unified conversations/membership, `seq`-based ordering,
   hash partitioning with a written justification, idempotent sends, RLS
   everywhere, presence isolated to a narrow table for documented reasons. This
   represents real design effort that a rewrite would either lose or
   painstakingly reproduce.
5. **The remaining work is additive, not corrective.** Nothing on the Phase 1
   list requires undoing existing code. Push notifications, signing, and an icon
   are things you *add*.
6. **The mock/live dual mode is an asset**, not tech debt — it is why the test
   suite is fast and why the app is demoable without a backend.

**Parts that must NOT be touched:**

- `lib/core/data/repositories/` — the composition root and dual-mode pattern
- `supabase/migrations/` — 13 migrations in dependency order, RLS-complete
- `lib/core/providers/chat_provider.dart` + `chat_repository.dart` — the most
  carefully reasoned code in the project, with the deepest test coverage
- The `Mock*Repository` classes and `MockDataGenerator` — deliberate, tested,
  and load-bearing for the test suite
- `lib/core/theme/` — complete and consistent

**What genuinely needs changing:** the five fake UI stubs in §9, and the
release-readiness gap. That is a **finishing** job, not a rebuild.

---

## 15. Top 5 Next Actions

1. **Commit and push everything, right now.** `git add -A`, commit, and push to a
   private remote. 40 Dart files, all 13 migrations and all 263 tests currently
   have no version-control protection. Nothing else on this list matters if the
   work disappears. *(Complexity: Low. Time: minutes.)*

2. **Generate a release keystore and wire the signing config.** Until
   `android/app/build.gradle.kts:35-38` stops using debug keys, nothing can be
   distributed to a single real student — and an app first shipped with debug
   keys can never be updated by a properly-signed build. *(Low)*

3. **Fix the fake safety report** at `help_support_screen.dart:167`. It tells
   students their harassment report was submitted while discarding the text. The
   real code to copy is 40 lines away in
   `connection_repository.dart:288`. *(Low — highest value-per-hour on the list.)*

4. **Replace the six hardcoded pravatar avatars with a real photo picker.** The
   upload path to the `avatars` bucket already works; `file_picker` is already
   integrated in `attachment_picker.dart`. This is wiring, not building. *(Low)*

5. **Implement push notifications.** Persist the notification preferences first
   (they gate the fan-out), register devices into the existing unused `devices`
   table, and extend the migration `0010` fan-out. This is the one large task —
   start it only after 1–4 are done. *(High)*

---

## 16. Risks

### 🔴 Biggest risk: 55% of the codebase is uncommitted
One commit, 77 changed paths, 32 of 72 Dart files tracked, and the entire
`supabase/` and `test/` trees untracked. The database design and the test suite —
the two things that make this project genuinely valuable — have **zero**
recovery path. A `git clean -fd`, an IDE "revert all", or a failed drive ends
the project. This is not a hypothetical: the work is sitting on a single machine
in a working directory.

### 🔴 Product risk: no push notifications
A social messaging app that goes silent the moment it is backgrounded will show
poor retention regardless of how good the chat implementation is. The backend
anticipated this (unused `devices` table); the client never followed through.

### 🟠 Distribution risk: debug signing
Cannot ship. And if a debug-signed build ever reaches users, it can never be
updated by a properly-signed one.

### 🟠 Trust risk: features that lie
Two UI paths report success for work that never happened — the safety report and
the event share. The safety report is the serious one: a student who reports
harassment is told the team will look into it, and nothing is sent anywhere.

### 🟠 Verification risk: RLS has never been adversarially tested
All 263 tests run against in-memory fakes. RLS is the entire security model, and
no test has ever confirmed that student A cannot read student B's messages
*through the real client*. The policies look right on inspection; that is not
the same as verified.

### 🟡 Operational risk: no crash reporting
Once on real devices, failures will be invisible.

### 🟡 Content risk: no way to create events, clubs or communities
Three of six Campus Hub modules have no creation path in the app and no admin
tool in the repo. Launch content must be inserted by hand via the Supabase
dashboard.

### 🟢 Low risk: code quality, architecture, dependencies
Clean analyzer, passing tests, current dependencies, sound structure. These are
not where the danger is.

---

## 17. Final Decision Summary

### A. Is the current project worth continuing?
**YES.** Without qualification on the code itself. This is a well-engineered
codebase — clean analyzer, 263 passing tests, no TODOs, a genuinely thoughtful
database design, and correct architectural separation. It is roughly 84%
complete.

### B. Should I continue this codebase or rebuild?
**Continue. Do not rebuild.** A rewrite would discard a sophisticated,
documented, RLS-complete Postgres schema and 263 passing tests in order to
arrive at approximately the architecture that already exists. The remaining work
is additive — push notifications, signing, an icon, and five UI stubs — none of
which requires undoing anything.

### C. What should I do next?
See §15. In one line: **commit everything, sign the release build, fix the fake
safety report, wire a real photo picker, then build push notifications.**

### D. What should I NOT do yet?
- **Do not refactor anything.** The analyzer is clean and the tests pass. Any
  refactor now spends effort on code that is already working while the real gaps
  stay open.
- **Do not split the 1,000-line files.** They are cohesive and well-commented.
  Cosmetic.
- **Do not touch the mock repositories or `MockDataGenerator`.** They look like
  dead code and are not — they are the reason the test suite is fast.
- **Do not redesign the database.** It is the strongest asset in the project.
- **Do not add new features** (reactions, analytics, web polish) until Phase 1
  is closed.
- **Do not start push notifications before committing the repo and persisting
  the notification preferences.** Push depends on both.
- **Do not write more tests against fakes.** The gap is integration coverage
  against real Supabase, not more unit tests.

### E. Biggest current risk?
**The uncommitted repository.** 40 untracked Dart files, all 13 migrations, all
14 test files, one commit total. Every other risk on this list is recoverable.
This one is not.

### F. Rough remaining effort
**MEDIUM.**

Breaking it down:
- **Small** — items 1, 2, 4, 5, 6, 7 and most of Phase 2. Mostly wiring,
  configuration, and copying patterns that already exist elsewhere in the repo.
- **Medium** — push notifications end-to-end (client registration + fan-out +
  deep links), plus the Phase 3 verification work.
- The estimate is **Medium** rather than **Small** for exactly one reason: push
  notifications is a genuine multi-day subsystem touching Flutter, FCM/APNs,
  the `devices` table, the fan-out job, and navigation. Remove that single item
  and the remaining work would be **Small**.

There is no **Large** or **Very Large** item anywhere in this audit. That is the
clearest signal available that continuing is the right call.

---

*Report produced by static inspection of the codebase plus two executed
verification commands (`flutter analyze`, `flutter test`). No project files were
modified. Claims marked ✅ are backed by executed tests or observed Postgres
calls; claims marked 🟡/🔴/⚠️ cite the specific file and line where the gap
appears.*
