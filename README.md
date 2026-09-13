# 🃏 RTC Hub — Richfield Tech-Connect Hub

**A professional network for the Richfield/AAA community, built around proof of
work rather than job titles.**

Students, alumni, recruiters and administrators share one platform: a
faculty-scoped feed, peer-to-peer bounties that pay out in Logic Points,
runnable code and working spreadsheets attached to posts, verified skills and
recommendations, and opportunity listings matched against what a student can
actually do.

Built for the 2026 Richfield Hackathon. Android and iOS.

---

## Stack, and why

Every choice below is a deliberate one; the reasoning matters as much as the
pick.

| Layer | Choice | Why this one |
| --- | --- | --- |
| **Mobile framework** | Flutter 3.41 / Dart 3.11 | One codebase for Android and iOS, which a team of four can actually maintain in the time available. Native performance for the video and syntax-highlighting work, and a widget model that made the five-theme system a palette swap rather than a rewrite. React Native was the alternative; Flutter won on the team already knowing Dart and on the tooling being one SDK rather than a JS toolchain. |
| **Database** | PostgreSQL (via Supabase) | The data is overwhelmingly relational — a student has skills, connections, posts, applications; a bounty payout has to be atomic across three tables. Document stores make those joins the application's problem. Postgres also gives row-level security, which is what lets us enforce access **in the database** instead of in the client. |
| **Backend** | Supabase — Postgres, Auth, Realtime, Storage | Removes the need for an application server entirely. Auth handles identity, Realtime replaces a socket server, Storage replaces an upload service. What is left is schema and policy, which is where the interesting decisions live. |
| **State** | Riverpod | Compile-time safe providers, trivial override points (demo mode is one `ProviderScope`), and `autoDispose` families that match how the screens are keyed. |
| **Navigation** | go_router | Declarative routes with a synchronous redirect for the auth gate, and `StatefulShellRoute` for tabs that keep their scroll position. |
| **Code execution** | Paiza.io | Snippets are executed in a real sandbox, not simulated. Piston was the first pick and went whitelist-only in Feb 2026; Wandbox's backend was failing every submission. Paiza's guest tier needs no key and was verified working across eight languages. |
| **Spreadsheets** | `excel` + Excel/Sheets hand-off | The app exports a real `.xlsx` and lets Excel recalculate it. Excel is already a spreadsheet engine that every Business student has; shipping our own formula evaluator would only produce numbers that disagree with the ones the user sees. |
| **Video** | `video_compress` on-device | §2.8 rejects raw uploads. Supabase has no transcoding primitive, and an Edge Function would have to receive the raw file first — the exact thing being avoided. A phone has a hardware encoder sitting idle. |
| **AI** | Google Gemini | Powers the onboarding assistant, the ongoing chatbot and CV skill extraction. A real model call, not a scripted response tree. |

### There is no application server

The app talks to Supabase directly with an **anon key**, so row-level security
is the real authorization boundary, not a decorative layer behind a trusted
API. Anything a user must not be able to forge is either denied by policy or
funnelled through a `SECURITY DEFINER` function. The previous React + Express
version — where a service-role key made RLS irrelevant — is kept under
[`legacy/`](legacy/) for reference and is not built or run.

This is also why role-based access holds up under inspection: a hand-rolled
HTTP request with a valid token gets exactly what the policies allow, and
nothing more.

---

## Getting started

### 1. Create the database

Run the migrations in the Supabase SQL editor, **in filename order**:

```
0001_initial_schema.sql            schema, enums, views, base policies
0002_client_direct_access.sql      signup trigger, bounty payout, RLS
0003_fix_profiles_rls_recursion.sql
0004_grant_table_privileges.sql
0006_b_student_dashboard.sql       student analytics
0006_fix_client_access.sql         AAA domains, FK cascades, grants
0007_b_dashboard_signals.sql       programme completeness, skill demand
0007_faculty_segregation.sql       IT/Business scoping, ranked feed
0008_b_business_skill_searches.sql
0008_submissions_and_sheets.sql    bounty submissions, spreadsheets
0009_a_onboarding_chat.sql         AI assistant storage
0009_notification_coverage.sql
0010_scan_fixes.sql                leaderboard privacy, server-side counts
0011_profiles_recommendations_saves.sql
0012_dashboard_analytics.sql       admin + business dashboards
0013_profile_portfolio.sql         §2.3 portfolio, career pathways
0014_alumni_verification.sql       alumni identity flow
```

They build on each other; running them out of order will fail.

`backend_profile_auth.sql` is a helper for attaching a profile to an account
created directly in the Supabase dashboard. It is not part of the sequence.

**Create the administrator by hand.** Admin accounts are deliberately not
self-registerable — `handle_new_user()` rejects `role = 'ADMIN'` outright.
Create the user in Supabase Auth, then promote them:

```sql
update profiles set role = 'ADMIN', status = 'ACTIVE'
where email = 'admin@richfield.ac.za';
```

**Enable `pg_cron`** (Database → Extensions) if you want unsolved bounties to
escalate and read notifications to be pruned:

```sql
select cron.schedule('escalate-bounties', '0 * * * *',
                     $$select escalate_bounties()$$);
select cron.schedule('prune-notifications', '0 3 * * *',
                     $$select prune_notifications()$$);
```

### 2. Point the app at your project

```bash
cp env.example.json env.json     # then fill in the URL and anon key
```

Use the **anon/publishable** key, never `service_role` — the service key
bypasses every policy and would make the security model meaningless.
`env.json` is gitignored; share the keys out of band.

For the AI assistant, add your Gemini key to the same file.

### 3. Run it

```bash
.\run              # Windows
./run.sh           # macOS / Linux
```

The wrappers pass the `--dart-define` flags for you. `.\run demo` starts the
offline walkthrough instead, with canned data and no backend at all — useful
for reviewing layout, and for a demo that survives dead campus wifi. Demo mode
routes around RLS by construction, so never use it to show that an access rule
works.

---

## Commands

```bash
.\run                                            # debug on a connected device
.\run demo                                       # UI only, no Supabase needed
./run.sh / ./run.sh demo                         # same, on macOS and Linux

# what the wrappers expand to, if you prefer typing it out:
flutter run --dart-define-from-file=env.json
flutter run --dart-define=DEMO=true

flutter analyze                                  # kept at zero issues
flutter test
flutter build apk --release --dart-define-from-file=env.json
flutter build ipa --release --dart-define-from-file=env.json   # needs macOS
```

---

## What is built

Mapped to the hackathon brief, so a reviewer can find things.

### §2.1 User types and authentication
Four roles — student, alumni, business, administrator — with access enforced in
RLS rather than by hiding screens. Students register on a Richfield or AAA
domain with a nine-digit student number, checked in `handle_new_user()` as well
as the client. Businesses wait for administrator approval. Administrators
cannot self-register at all.

**Alumni identity verification** is the interesting one, because the
institution's strongest signal — the student mailbox — is exactly what has
expired for this group. A claimed student number and graduation year are
submitted alongside a graduation certificate, transcript or student card, and
an administrator reviews the claim and the document side by side. The claim is
frozen once submitted and self-approval is blocked by trigger, so the review
means something. The reasoning behind the design, and the two approaches that
were rejected, are written into `0014_alumni_verification.sql`.

### §2.2 Administrator panel
User management, content moderation, opportunity approval, institutional event
creation and editing, platform-wide announcements, and a charted analytics
dashboard.

### §2.3 Profiles as portfolios
Headline, bio, campus, enrolment and graduation years, skills, work experience,
entrepreneurial ventures, GitHub profile and per-repository portfolio, deployed
app links, digital badges, certifications, Credly and LinkedIn links, academic
achievements, leadership roles, clubs and activities, career interests, CV
upload, and company profiles for businesses.

**Per-section visibility is enforced server-side.** Hidden sections are removed
by `profile_for_viewer()` before the profile leaves the database — they are
absent from the response rather than merely unrendered, because hiding them in
the client would leave the data on the device.

Skill endorsements and written recommendations, the latter invisible until the
subject approves them.

### §2.4 Connections and feed
Connection requests, a relevance-ranked feed that scores and weights
differently per role, text posts, **short-form video** with on-device
compression and thumbnail generation, direct messaging over Realtime, comments
and reactions.

**Faculty scoping runs through all of it.** IT and Business are separate
audiences: a post reaches its own faculty plus the businesses recruiting from
it. Enforced in the `posts_select` policy, not in the queries.

### §2.5 Opportunities and careers
Business listings subject to administrator approval, student applications with
status tracking, a career pathway explorer showing where alumni from a
programme ended up, and institutional events with targeted notifications.

### §2.6 Onboarding and AI assistant
A first-run tutorial, a Gemini-backed profile assistant that gives
context-aware feedback, and an ongoing chatbot.

### §2.7 Three analytics dashboards
Separate student, business and administrator dashboards, each visualised with
charts rather than raw numbers.

### §2.8 Technical features
Realtime notifications over WebSockets (never polling), skill-and-programme
based job matching, NLP skill extraction from an uploaded CV, and video
compression with thumbnail generation before storage.

### Beyond the brief
Bounties that pay out in Logic Points, runnable code for IT students,
spreadsheet posts that open and recalculate in Excel for Business students,
saved items, unified search, connection suggestions, and five selectable
themes.

---

## Layout

```
lib/
  core/        Supabase client, theme, router, constants, demo data
  models/      Row → Dart mappings, hand-written
  data/        One repository per feature area, plus the non-Supabase services
  features/    Screens, grouped by feature
  widgets/     Shared UI — charts, skeletons, code blocks, video, sheets
  providers.dart
supabase/migrations/
legacy/        Archived React + Express version, not built
```

For the architecture and the security model behind it, see
[CLAUDE.md](CLAUDE.md).

---

## Team

Work is split across parallel branches — see **[WORKPLAN.md](WORKPLAN.md)** for
who owns what, the file-ownership rules that keep the branches from colliding,
and the timeline to the 15–16 September campus round.
