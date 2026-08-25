# 🗄️ RTC Hub — Supabase

The database is the backend. The Flutter app connects with an anon key and holds
no privileged credentials, so everything that used to live in Express route
handlers now lives here.

## Applying migrations

Run these in the Supabase SQL editor, in order:

1. `migrations/0001_initial_schema.sql` — tables, enums, views, indexes, and the
   first pass at RLS.
2. `migrations/0002_client_direct_access.sql` — everything needed to reach the
   database safely without a server in front of it.

`0002` is required. `0001` enables row-level security on twenty tables but only
writes policies for nine of them, and RLS with no policy denies everything — so
on `0001` alone most of the app cannot read or write at all.

## What 0002 adds

**Signup.** `handle_new_user()` fires on `auth.users` insert and builds the
`profiles` row from the metadata passed to `signUp()`. It enforces the Richfield
domain and 9-digit student number, sets students ACTIVE and everyone else
PENDING, creates the onboarding row, and notifies admins of accounts awaiting
review. It refuses to create an ADMIN.

**Guards.** BEFORE triggers strip fields a client could benefit from lying
about: `profiles.role` / `profiles.status` / `profile_completeness`,
`posts.bounty_points` / `bounty_solved` / `is_flagged`, `comments.is_solution`,
and `opportunities.status`.

**Notifications.** `notifications` cannot be written for another user, so every
cross-user notification is raised by a trigger — reactions, comments, messages,
connection requests and acceptances, endorsements, account status changes.

**Bounty payout.** `accept_bounty_solution(comment_id)` checks that the caller
posted the bounty, that it is unsolved, and that they are not accepting their
own answer, then closes it and writes the `logic_points` row. The ledger has a
SELECT policy and no INSERT policy, so this function is the only way points are
ever created. (The old API let the commenter set `is_solution` themselves and
award their own points.)

**Matching.** `matched_opportunities()` scores live listings against the
caller's skills, faculty and year — this replaced `services/matchingService.js`.

**Storage.** Four buckets: `avatars` and `post-media` are public, `documents`
and `verification` are private. Policies derive ownership from the first path
segment, so objects must be stored as `<uid>/<filename>`.

## Operational notes

- **Make an admin** by promoting an existing account:
  `UPDATE profiles SET role='ADMIN', status='ACTIVE' WHERE email='…';`
- **Bounty escalation** (`escalate_bounties()`, from 0001) raises unsolved
  bounties by 5 points a day up to 500. It needs scheduling — enable `pg_cron`
  and add a daily job, or call it from a scheduled Edge Function. Nothing runs
  it automatically.
- **Realtime** publishes `messages`, `notifications`, `posts`, `connections` and
  `comments`. RLS is applied per subscriber, so channels deliver only rows the
  user could already read.
