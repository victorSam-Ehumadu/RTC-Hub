# RTC Hub — Team Workplan

Three parallel development streams, one branch each, taking the app from where
it is now to a submission that satisfies **every mandatory requirement** in
`docs/2026 Hackathon Guidelines .pdf` and `docs/Project Break Down.pdf`.

**Campus round: 15–16 September 2026. National: 17 September.**

Read `CLAUDE.md` before starting. The short version: the guidelines and project
breakdown are binding, the proposal (Logic Points, bounties, Shadow-a-Senior) is
already built and scores zero on the rubric — **do not add to it until the
mandatory list below is closed.**

---

## Prerequisite — do this before anyone branches

The Flutter rewrite currently exists only on one machine and is uncommitted.
Nobody can branch off nothing.

1. Land the current work on `main` as a series of logical commits (archive web
   app → scaffold Flutter → migration → data layer → screens → docs).
2. Push `main`.
3. Everyone: `git clone`, then `flutter pub get`, then create `env.json` from
   `env.example.json` (ask for the Supabase keys — they are gitignored, never
   commit them).
4. Run both migrations in `supabase/migrations/` against the shared Supabase
   project, in order.

Until step 2 is done, the rest of this document is theoretical.

---

## Stream A — AI, Onboarding & Assistant

**Branch:** `feat/ai-assistant`

The heaviest stream and the one most likely to sink the submission if it slips.
It is four mandatory requirements behind a single Gemini integration, and
**none of it exists yet.**

### Requirements covered

| Ref | Requirement |
| --- | --- |
| §2.6 | AI profile assistant guiding new users through completing their profile |
| §2.6 | Context-aware feedback ("no skills listed" → won't appear in recruiter searches) |
| §2.6 | Ongoing chatbot users can return to with questions |
| §2.6 | Interactive first-run app tutorial |
| §2.8 | NLP-assisted profile building — extract skills from an uploaded CV |

### Watch out

The brief explicitly rejects **"a hardcoded script of fixed responses"**. This
must be a real model call. It also calls onboarding **"not optional — a core
feature of the platform"**, so a stub will be marked as missing, not partial.

### Owns these files

```
lib/features/onboarding/**      (new)
lib/features/assistant/**       (new)
lib/data/ai_repository.dart     (new)
supabase/migrations/0003_*.sql  (onboarding state, chat history)
```

### Done when

- A new user is walked through profile completion on first login by a live model
- The assistant is reachable later from the profile screen and answers freeform
  questions about the platform
- Uploading a CV populates suggested skills the user can accept or reject
- A first-run tutorial walks the key screens
- `onboarding_progress.tutorial_complete` is actually written and respected

---

## Stream B — Analytics, Dashboards & Feed

**Branch:** `feat/analytics-dashboards`

### Requirements covered

| Ref | Requirement |
| --- | --- |
| §2.7 | **Student** dashboard: profile views over time, connection growth, post engagement, completeness vs. programme peers, most-searched skills |
| §2.7 | **Business** dashboard: applicant pipeline per listing, listing engagement, candidate skill distribution, applicant breakdown by programme and year, profile reach |
| §2.7 | **Administrator** dashboard: users by type, monthly active users, registrations over time, content volume, flagged count, business approval pipeline |
| §2.5 | Career pathway explorer — alumni trajectories for the student's programme |
| §2.4 | Feed ranked by relevance, behaving differently per role |

### Watch out

Two clauses will fail you if ignored:

- *"Three distinct dashboards — a single generic statistics page shared across
  user types will not satisfy this requirement."* Three screens, not one with a
  role switch.
- *"Raw numbers displayed without visualisation will not satisfy this
  requirement."* Every dashboard needs charts. `fl_chart` is already a
  dependency and currently unused.

The existing four-number row on the profile screen and the tile grid in the
admin console are **not** dashboards. Treat them as placeholders to replace.

The `career_pathways` SQL view already exists in migration 0001 and has no UI
reading it — that one is mostly a screen.

### Owns these files

```
lib/features/analytics/**       (new)
lib/features/pathways/**        (new)
lib/features/admin/admin_screen.dart   (Overview tab → real dashboard)
lib/data/admin_repository.dart  (AnalyticsRepository)
lib/data/post_repository.dart   (feed ranking only)
supabase/migrations/0004_*.sql  (aggregate RPCs, MAU, skill-search counts)
```

### Done when

- Three separate dashboard screens exist, each with charts
- Every metric listed above renders from real data, not placeholders
- A student can see where alumni from their programme ended up
- The feed returns a different ordering for a student vs. a business account

---

## Stream C — Profiles, Media & Identity

**Branch:** `feat/profiles-media`

The most items, individually the smallest — good for splitting further if this
person needs help.

### Requirements covered

| Ref | Requirement |
| --- | --- |
| §2.3 | ~17 profile fields (see below) |
| §2.3 | Written recommendations and testimonials |
| §2.3 | Per-section profile visibility controls |
| §2.3 | Business company profile: website, contact details, talent sought |
| §2.1 | **Alumni authentication and identity verification flow** |
| §2.1 | Accept `@my.aaa.ac.za` and `@aaa.ac.za` student domains |
| §2.8 | Video upload with compression/transcoding and thumbnail generation |

### Profile fields still missing

Professional headline · professional summary · campus attended · year of
enrolment · GitHub profile link · portfolio of GitHub projects with repo links ·
portfolio of apps with live URLs · digital badges · professional certifications ·
Credly profile link · academic achievements and awards · leadership roles (SRC,
class rep, mentor) · clubs, societies and competitions · career interests ·
LinkedIn link

Existing profile has bio, skills, work experience, CV upload, portfolio URL.
Everything else on that list is new schema plus new UI.

### Watch out

**Alumni auth is the trap.** The brief calls it *"a deliberate design challenge;
there is no prescribed solution"* and warns it *"must be addressed with a
researched, reasoned solution, not left as a gap."* Right now alumni are treated
as ordinary pending accounts — which is precisely the gap. Design something
defensible (student number + graduation year + document upload + admin
verification is a reasonable starting point) and **write down the reasoning**,
because it has to be justified in the presentation.

**Video cannot be done client-side.** Transcoding needs a Supabase Edge Function
running ffmpeg, or an external service (Mux, Cloudinary). The brief: *"Raw,
unprocessed video uploads dumped directly to storage are not acceptable."*
Start this early — it is the least predictable item in the whole plan.

The current student email check lives in two places and both need the AAA
domains: `isValidStudentEmail` in `lib/core/constants.dart`, and
`handle_new_user()` in migration 0002. Ship that fix on day one; it is minutes
of work against a mandatory clause.

### Owns these files

```
lib/models/profile.dart
lib/features/profile/**
lib/features/auth/signup_screen.dart
lib/data/profile_repository.dart
lib/data/storage_repository.dart
lib/core/constants.dart
supabase/migrations/0005_*.sql  (profile columns, recommendations, visibility)
supabase/functions/**           (new — video transcoding)
```

### Done when

- Every §2.3 field is editable and displayed
- Someone can leave a written recommendation that appears on the recipient's
  profile
- A user can hide individual profile sections from specific audiences
- An alumnus can register and be verified through a documented, working flow
- A student can post a video that is transcoded and has a generated thumbnail

---

## Shared files — conflict protocol

Three branches touching one file is where this goes wrong. These four are shared
by all streams:

| File | Rule |
| --- | --- |
| `pubspec.yaml` | Add your dep, commit **that line alone**, push same day. Never reformat the file. |
| `lib/core/router.dart` | Add routes at the **end** of the routes list. Never reorder existing entries. |
| `lib/providers.dart` | Add providers at the **end** of your feature's section. Never reorder. |
| `supabase/migrations/` | **Never edit an existing migration.** Each stream owns its own number: A→0003, B→0004, C→0005. Further migrations: `0006_a_*`, `0007_b_*` etc. with your stream letter. |

Everything else in the ownership lists above belongs to exactly one stream. If
you need to change another stream's file, message them first — do not just edit
it.

---

## Git workflow

```bash
git checkout main && git pull
git checkout -b feat/your-stream

# daily, before you start:
git checkout main && git pull
git checkout feat/your-stream
git rebase main          # resolve conflicts while they are small

# push often:
git push -u origin feat/your-stream
```

**Merge to `main` via pull request**, reviewed by one other person. Merge working
increments as they land — do not sit on a branch for two weeks and merge
everything on the 13th.

### On commit history — this is graded

The brief states: *"Commit history must reflect meaningful, distributed
contributions from all team members throughout the project period. A repository
with a single large commit or contributions from only one or two members will be
treated as evidence of non-compliance."*

So: **commit under your own name, for work you actually did.** Small, frequent,
descriptive commits. Do not batch a week into one commit, and do not commit on
someone else's behalf — if a judge asks you to explain code with your name on it,
you need to be able to.

---

## Timeline

| Dates | Milestone |
| --- | --- |
| 26 Aug | `main` pushed, everyone cloned and running, branches created |
| 26 Aug | AAA email domains fixed and merged (Stream C, day one) |
| 26–1 Sep | A: Gemini talking to the app · B: student dashboard · C: profile schema + video spike |
| 2 Sep | **Checkpoint 1** — every stream has one thing merged to `main` |
| 2–8 Sep | A: assistant + tutorial · B: business + admin dashboards · C: remaining fields, recommendations, alumni flow |
| 9 Sep | **Checkpoint 2** — walk the guidelines section 2 as a checklist, together. Anything not started gets cut or triaged here |
| 9–12 Sep | A: CV parsing · B: pathways + feed ranking · C: video pipeline finished |
| **12 Sep** | **Code freeze.** Only bug fixes after this |
| 13–14 Sep | Integration testing, demo rehearsal, deck finished |
| 15–16 Sep | Campus round |

Checkpoint 2 on 9 September is the honest one: three days from freeze is the
last point where cutting scope is a decision rather than an accident.

---

## Not covered by these three streams

These belong to the rest of the team, and they are graded deliverables:

- **PowerPoint deck, minimum 15 slides** — problem statement, all four user
  types and access levels, authentication design (including the alumni solution
  and admin provisioning), system architecture diagram, database and framework
  justification, AI assistant design, one slide per analytics dashboard, and
  POPIA compliance. Start it in week one, not the night before.
- **Demo script** — the live demo must show all four user types including the
  admin panel. Seed accounts for each role, rehearse the flow, and narrate it.
  The brief marks down demos that crash or that the panel has to interpret
  unaided.
- **POPIA compliance** — a required slide and worth a real answer, given the app
  stores CVs, ID-adjacent verification documents, and student data.

## Two things to confirm with the coordinator

- **Registration deadline was 21 August 2026.** Confirm the team is registered.
- **Team size**: the guidelines say 7–10 students, the invitation letter says 5.
  Ask which governs.

---

## Demo strengths worth protecting

Whatever else gets cut, these already work and answer requirements most teams
will miss. Do not refactor them late.

- **Backend-enforced RBAC.** The guidelines demand it and warn that *"hiding
  screens on the front end alone is insufficient."* Access control is Postgres
  RLS, not UI conditionals — provable live by signing in as a student and
  watching an admin query return nothing.
- **Admins cannot self-register.** The signup trigger raises an exception on
  `role = 'ADMIN'`. One SQL statement demonstrates it.
- **Real-time is WebSockets, not polling** — Supabase Realtime. The brief
  rejects polling explicitly.
- **Job matching is real matching logic**, not a broadcast — `matched_opportunities()`
  scores skills, faculty and year.
