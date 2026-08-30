# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source of truth — read this first

This project is a submission for the Richfield Hackathon 2026. The briefs live
in `docs/`, and they rank strictly:

1. **`docs/2026 Hackathon Guidelines .pdf`** and **`docs/Project Break Down.pdf`**
   are binding. Follow them *strictly*. Every requirement in section 2 of the
   guidelines is mandatory, and the brief states plainly that a prototype
   omitting any of them "will be assessed as incomplete, regardless of the
   quality of what is present". Treat any conflict with the code as the code
   being wrong.
2. **`docs/Hackathon 2026 proposal.pdf`** is our own pitch — Logic Points,
   bounties, Shadow-a-Senior, skill graphs, leaderboards. These are
   differentiators, not requirements. **Do not build or extend proposal features
   until every mandatory requirement above is met.** Where a proposal feature
   already exists and a mandatory one does not, the mandatory one wins the next
   hour of work.
3. **`docs/Tech Stack Breakdown.pdf`** is a starting point, not a contract.
   Flutter + Supabase + Gemini is the assumed stack, but substitute freely where
   there is a better tool for what a requirement actually needs. Note that the
   guidelines require every stack choice to be *justified in the presentation*,
   so record the reasoning for any deviation.
4. **`docs/Richfield Hackerthon 2026 IT Students Invitation Letter.pdf`** is for
   dates only: campus round **15–16 September 2026**, national round
   **17 September 2026**.

Two guideline clauses bear directly on how work should be done here:

- Role-based access **must be enforced on the backend** — "hiding screens on the
  front end alone is insufficient." This is why the RLS model below is
  non-negotiable, and it is the strongest card this project holds.
- Commit history "must reflect meaningful, distributed contributions from all
  team members". A repo carrying one or two authors is explicitly called
  non-compliance, so prefer small scoped commits the team can share over large
  batched ones.

## What this is

RTC Hub — a Flutter app for the Richfield College community: a feed of code
posts, a bounty board where students earn Logic Points for solving each other's
problems, business-posted opportunities, direct messaging, events, and an admin
console. Android and iOS.

**There is no application server.** The app is a Supabase client, and the
database is the backend. An earlier React + Express version lives under
`legacy/` and is not built, run, or imported — treat it as documentation of
prior intent, nothing more.

## Commands

```bash
flutter run --dart-define-from-file=env.json     # debug on a device
flutter analyze                                  # keep this at zero issues
flutter test                                     # unit tests
flutter test test/models_test.dart               # one file
flutter build apk --debug --dart-define-from-file=env.json
flutter run --dart-define=DEMO=true              # UI walkthrough, no backend
```

Credentials come from `env.json` (gitignored; copy `env.example.json`) via
`--dart-define-from-file`. `Env.isConfigured` is false without them and `main()`
shows a setup screen rather than crashing — so a build that "works" but shows
that screen means the define was missing, not that the code is broken.

`--dart-define=DEMO=true` is the exception: it skips `Supabase.initialize`
altogether and swaps the repository providers for the canned data in
`lib/core/demo.dart`, so the app runs with no project and no keys. It exists to
review layout and copy, and for a demo that survives dead campus wifi. It routes
around RLS by construction, so never use it to show that an access rule works —
that claim can only be demonstrated against a real project.

Database changes are SQL files in `supabase/migrations/`, applied by pasting
them into the Supabase SQL editor in filename order. There is no Supabase CLI
setup and no local Postgres; a schema change means editing SQL and re-running it
against the project.

## The security model — read this before touching data access

This is the single most important thing about the codebase, and it inverts how
the old Express version worked.

The Express API held a **service-role key**, so RLS was decorative and route
handlers were the authorization boundary. The app holds an **anon key**, so:

- **RLS policies are the real boundary.** Every query is filtered by the
  signed-in user's JWT. A missing policy means "denied", not "allowed" — which
  is why migration `0002` had to add policies for the eleven tables `0001`
  enabled RLS on but never wrote policies for.
- **Anything a user must not forge is not writable by them.** `logic_points` has
  a SELECT policy and no INSERT policy at all. `notifications` cannot be written
  for another user. `profiles.role` and `profiles.status` are reverted by
  `trg_profiles_guard` unless `is_admin()`. `posts.bounty_points`,
  `posts.is_flagged` and `comments.is_solution` are likewise stripped from
  client writes by BEFORE triggers.
- **Privileged work happens in `SECURITY DEFINER` functions**, called via
  `db.rpc(...)`. `accept_bounty_solution` is the model: it verifies the caller
  owns the bounty, closes it, writes the ledger row, and notifies the winner —
  all things the client is specifically forbidden from doing directly.

The practical rule when adding a feature: if the operation writes data on
someone else's behalf, or writes a field a user could benefit from lying about,
it belongs in a trigger or an RPC in a new migration — not in a repository
method. Adding it to Dart will simply fail at runtime with a 42501.

Note that `handle_new_user()` runs on `auth.users` insert and builds the
`profiles` row from `raw_user_meta_data`. Signup therefore passes profile fields
through `signUp(data: {...})`, never a separate INSERT.

## Architecture

**Layers**: `features/` (screens) → `providers.dart` (Riverpod) →
`data/` (repositories) → `core/supabase.dart` (the client). Screens never touch
`db` directly; repositories never touch widgets. Each repository maps to what
used to be one Express route group, and the doc comment on each says which one.

**`providers.dart` is a single file on purpose.** Everything is a
`FutureProvider.autoDispose`, usually `.family` keyed by an id. After a mutation
the convention is `ref.invalidate(thatProvider)` rather than local mutation —
except in `PostCard`, which applies reactions optimistically and rolls back on
failure, because a round-trip per tap made the feed feel dead.

**Auth gating happens in two places, deliberately.** The go_router `redirect`
only checks whether a session exists, because a `redirect` must be synchronous.
Whether the *account* may enter — PENDING businesses, SUSPENDED users — is
decided by `AppShell`, which awaits `myProfileProvider` and swaps in
`AccountGateScreen`. Do not try to move the status check into the redirect.

**Realtime replaced Socket.IO.** `threadProvider` and `unreadCountProvider` are
`StreamProvider`s that seed from a query and then append from a Supabase channel,
disposing it via `ref.onDispose`. Realtime applies RLS per subscriber, so a
channel on `messages` only ever delivers rows the user can already read — which
is why `MessageRepository.subscribe` can subscribe to the whole table and let
callers narrow with `Message.inThread`.

**Bounties are posts**, not a separate entity, and the payout is the RPC
described above. Logic Points totals come from `total_logic_points(uid)` summing
the ledger — never a stored counter.

**The feed is connection-scoped**: `PostRepository.feed()` resolves the caller's
ACCEPTED `connections` (symmetric — the user may be either side) and then filters
posts to that id set. `discover()` exists because the connection-scoped feed is
empty for a new user, which the web version never handled.

**Models are hand-written** `fromMap` constructors — no `json_serializable`, no
`build_runner`. Keep it that way; adding codegen means a generation step in
every workflow. PostgREST returns embedded aggregates as `[{"count": n}]`, which
is what `embeddedCount` in `models/profile.dart` unpacks.

## Staying in sync with the team

Three people work this repo in parallel from three branches (see
`WORKPLAN.md`), each driving Claude Code. Overlapping edits are the main risk,
so treat syncing as part of the task, not as a chore at the end:

- **Start every working session with `git fetch --all --prune` and a status
  check** against the tracking branch, before reading or editing anything.
  Reasoning about stale files is how two people rewrite the same widget.
- **Pull before you edit shared files.** `pubspec.yaml`, `lib/providers.dart`,
  `lib/core/router.dart` and `CLAUDE.md` are touched by all three streams;
  WORKPLAN's rule is that edits to them are append-only for exactly this
  reason.
- **Push as soon as a unit of work is committed**, so the others see it. Small
  scoped commits pushed often also satisfy the guidelines' requirement that
  history show distributed contribution.
- **Push to the feature branch, never straight to `main`.** `main` moves by
  pull request.
- If a pull conflicts, resolve it rather than reaching for `--force`. Never
  force-push a shared branch without the branch owner saying so.
- Migrations are numbered per stream (A→`0003`, B→`0004`, C→`0005`) so two
  people never claim the same filename. Check `supabase/migrations/` after a
  fetch before naming a new one.

## Conventions

- Storage objects **must** be written as `<uid>/<filename>` — the storage
  policies derive ownership from the first path segment, so any other layout is
  rejected.
- Errors reaching the UI go through `describeError` (`data/errors.dart`), which
  turns 42501 into "you do not have permission" and passes our own
  `RAISE EXCEPTION` text (P0001) straight through. Those messages are written
  for end users, so keep them that way when adding one.
- `TagChip`, not `Badge` — Material exports its own `Badge` and the collision is
  an analyzer error at every call site.
- The theme is dark-first ("terminal"), with monospace (`monoStyle`) reserved for
  code and numeric scores so technical content reads differently from prose.
- `flutter analyze` is at zero issues. Keep it there.
