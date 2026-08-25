# 🃏 RTC Hub — Richfield Tech-Connect Hub

**Moving from digital résumés to verifiable proof of work.**

A Flutter app for the Richfield College community. Where LinkedIn is saturated
with corporate noise, RTC Hub optimises for *technical signal*: code posts,
peer-to-peer bounties that pay out in Logic Points, module-verified skills, and
opportunities matched against what a student can actually do.

## Stack

| Layer | Choice |
| --- | --- |
| App | Flutter 3.41 / Dart 3.11 — Android + iOS |
| State | Riverpod |
| Navigation | go_router |
| Backend | Supabase — Postgres, Auth, Realtime, Storage |

There is **no application server**. The app talks to Supabase directly, and
row-level security plus a handful of `SECURITY DEFINER` functions are what
enforce the rules. The previous React + Express version is kept under
[`legacy/`](legacy/) for reference.

## Getting started

**1. Create the database.** In the Supabase SQL editor, run the migrations in
order:

```
supabase/migrations/0001_initial_schema.sql
supabase/migrations/0002_client_direct_access.sql
```

`0002` is not optional — it contains the signup trigger, the bounty payout, and
the policies that make the tables reachable at all.

**2. Point the app at your project.**

```bash
cp env.example.json env.json     # then fill in the URL and anon/publishable key
```

`env.json` is gitignored. Find both values under *Project Settings → API*.

**3. Run it.**

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

Launching without the credentials shows a setup screen instead of crashing.

**4. Make yourself an admin.** Sign up in the app, then in the SQL editor:

```sql
UPDATE profiles SET role = 'ADMIN', status = 'ACTIVE'
WHERE email = 'you@richfield.ac.za';
```

Admin is the one role that cannot be self-registered — the signup trigger
rejects it.

## Commands

```bash
flutter run --dart-define-from-file=env.json     # debug on a connected device
flutter analyze                                  # static analysis
flutter test                                     # unit tests
flutter build apk --release --dart-define-from-file=env.json
flutter build ipa --release --dart-define-from-file=env.json   # needs macOS
```

## How the product works

**Accounts.** Students register with a `@richfield.ac.za` address whose local
part is a 9-digit student number, and are active immediately — the domain *is*
the verification. Businesses and alumni land in `PENDING` and wait for an
administrator; until then the app shows them a holding screen rather than the
feed.

**Bounties.** A bounty is a post, not a separate thing. Posting one puts 10
Logic Points on the table, and unsolved bounties escalate over time. Only the
person who asked can accept an answer, and accepting is what moves the points —
through an RPC, because the points ledger is not writable by clients at all.

**Logic Points** are an append-only ledger. Totals are always summed, never
stored, so a balance cannot drift from the transactions behind it.

**Opportunities** posted by businesses are reviewed by an administrator before
students see them. Once live, they are scored against each student's skills,
faculty and year.

**Everything real-time** — messages, notifications — rides on Supabase Realtime,
which applies row-level security per subscriber.

## Layout

```
lib/
  core/        Supabase client, theme, router, constants
  models/      Row → Dart mappings
  data/        One repository per feature area
  features/    Screens, grouped by feature
  widgets/     Shared UI
  providers.dart
supabase/migrations/
legacy/        Archived React + Express version
```

For the architecture and the security model behind it, see
[CLAUDE.md](CLAUDE.md).

## Team

Work is split across three branches — see **[WORKPLAN.md](WORKPLAN.md)** for who
owns what, the file-ownership rules that keep the branches from colliding, and
the timeline to the 15–16 September campus round.
