# Five streams for five people

A redistribution of the three-stream plan in `WORKPLAN.md` across the actual
team: five people, one already on Stream B, one whose machine can't run
Android Studio. Requirement references are to
`docs/2026 Hackathon Guidelines .pdf` §2.

**Status: proposed, not yet adopted.** `WORKPLAN.md` still describes the
original 3-stream plan. This document exists so the split is visible to
everyone before anyone commits to it — if the team agrees to it, `WORKPLAN.md`
should be updated to match and this note removed.

- Team: 5 people
- Streams: 5 (4-stream fallback in §5 below)
- Campus round: 15–16 Sep 2026
- National round: 17 Sep 2026
- Code freeze: 12 Sep 2026

## Staffing mismatch — flag to the coordinator

The guidelines specify **7–10 students per group**; this team is **5**. Every
stream below is sized on the assumption that each person is doing roughly
double the work the brief assumes per head. That's the main argument for
leaning hard on AI-assisted ("vibe-coded") implementation for the repetitive
parts — form fields, chart wiring, CRUD screens — and spending human attention
where it can't be skipped: RLS policies, the alumni verification design, and
anything that touches money-equivalent state (Logic Points, bounty payouts).
Confirm with the coordinator which team-size figure actually governs before
presenting.

---

## 1. At a glance

Branches keep the existing names where a stream is a direct continuation of
`WORKPLAN.md`; two are new, split out of the old Stream C.

| Stream | Branch | Covers | Person | Relative load |
| --- | --- | --- | --- | --- |
| A | `feat/ai-assistant` | AI onboarding, assistant, CV parsing | Unassigned | Very high |
| B | `feat/analytics-dashboards` | 3 dashboards, pathways, feed ranking | Already assigned — keep, offer help | Very high |
| C | `feat/profiles-media` | Profile fields, endorsements, recommendations | Unassigned | High volume |
| D | `feat/identity-media` (new) | Alumni verification, video pipeline | Unassigned | Medium, high-risk |
| E | `feat/admin-ops` (new) | Admin panel, notifications, events, deck & demo | The no-Android-Studio person | Medium, back-loaded |

---

## 2. Per-stream breakdown

### Stream A — AI, Onboarding & Assistant

**Branch:** `feat/ai-assistant` · unchanged from `WORKPLAN.md`

Unchanged in scope — it was already sized right for one person, and it's the
stream most likely to sink the submission if it slips, so it stays solo
rather than being diluted. Four mandatory items sit behind one Gemini
integration that doesn't exist yet.

**Requirements**
- §2.6 — AI profile assistant that guides a new user through completing their profile, section by section
- §2.6 — Context-aware feedback ("no skills listed" won't surface in recruiter searches)
- §2.6 — Ongoing chatbot the user can return to with freeform questions
- §2.6 — Interactive first-run tutorial across the key screens
- §2.8 — NLP-assisted profile building — extract skills from an uploaded CV

**Owns**
```
lib/features/onboarding/**      (new)
lib/features/assistant/**       (new)
lib/data/ai_repository.dart     (new)
supabase/migrations/0003_*.sql  (onboarding state, chat history)
```

**Watch out** — the brief rejects "a hardcoded script of fixed responses"
outright — this has to be a live model call, not a decision tree with a chat
skin. It also calls onboarding "not optional — a core feature," so a
half-built stub reads as missing, not partial. Vibe-coding is fine for the
chat UI shell; the prompt design and the profile-field data contract with
Stream C need a human pass.

**Done when**
- A new user is walked through profile completion on first login by a live model, not a script
- The assistant is reachable later from the profile screen and answers freeform questions
- Uploading a CV populates suggested skills the user can accept or reject
- A first-run tutorial walks the key screens
- `onboarding_progress.tutorial_complete` is actually written and respected

---

### Stream B — Analytics, Dashboards, Feed & Pathways

**Branch:** `feat/analytics-dashboards` · current owner continues — flagged for help

The widest single-stream surface area in the plan: three separate
dashboards, each with several charted metrics, plus a pathway explorer and
feed re-ranking. If a second person joins, split at the seam below rather
than dividing files mid-screen.

**Requirements**
- §2.7 — Student dashboard: profile views over time, connection growth, post engagement, completeness vs. programme peers, most-searched skills
- §2.7 — Business dashboard: applicant pipeline per listing, listing engagement, candidate skill distribution, applicant breakdown by programme/year, profile reach
- §2.7 — Admin dashboard: users by type, MAU, registrations over time, content volume, flagged count, business approval pipeline
- §2.5 — Career pathway explorer — alumni trajectories for the student's programme
- §2.4 — Feed ranked by relevance, behaving differently per role

**Owns**
```
lib/features/analytics/**              (new)
lib/features/pathways/**               (new)
lib/features/admin/admin_screen.dart   (Overview tab only — shared with Stream E)
lib/data/admin_repository.dart         (AnalyticsRepository)
lib/data/post_repository.dart          (feed ranking only)
supabase/migrations/0004_*.sql         (aggregate RPCs, MAU, skill-search counts)
```

**Watch out** — "Three distinct dashboards — a single generic statistics page
shared across user types will not satisfy this requirement." Three screens,
not one with a role switch, and every metric needs a chart — `fl_chart` is
already a dependency and currently unused. The four-number row on the profile
screen and the admin tile grid are placeholders, not dashboards.

**If a second person joins** — split by dashboard, not by file: owner keeps
the student dashboard, feed ranking, and the pathway explorer; helper takes
the business and admin dashboards plus their aggregate RPCs. Both land in the
same `lib/features/analytics/` tree — coordinate before either touches a
shared widget in it.

**Done when**
- Three separate dashboard screens exist, each with charts
- Every metric listed above renders from real data, not placeholders
- A student can see where alumni from their programme ended up
- The feed returns a different ordering for a student vs. a business account

---

### Stream C — Profile Portfolio, Endorsements & Recommendations

**Branch:** `feat/profiles-media` · narrower than the old Stream C

The old Stream C's profile-fields half. High *volume*, not high *risk* —
around fifteen new fields, plus endorsements and recommendations, are almost
entirely repetitive form-and-schema work, which is exactly what vibe-coding
is good at. The parts that used to make this stream scary — alumni auth,
video — now live in Stream D.

**Requirements**
- §2.3 — ~17 profile fields: headline, summary, campus, enrolment/graduation year, GitHub link, GitHub repo portfolio, live-app portfolio, digital badges, certifications, Credly link, academic achievements, leadership roles, clubs/societies/competitions, career interests, LinkedIn
- §2.3 — Skill endorsements and written recommendations/testimonials from alumni, lecturers, mentors, employers
- §2.3 — Per-section profile visibility controls (business / students / alumni / lecturers / public)
- §2.3 — Business company profile: website, contact details, talent sought

**Existing fields:** bio, skills, work experience, CV upload, portfolio URL.
Everything else on the list above is new schema plus new UI.

**Owns**
```
lib/models/profile.dart
lib/features/profile/**
lib/data/profile_repository.dart
supabase/migrations/0005_*.sql  (profile columns, recommendations, visibility)
```

**Coordinate with**
- Stream A — the assistant reads profile completeness and skill data; agree on the shape of the skills list and what counts as "complete" before either builds against it.
- Stream E — owns "profile view" tracking calls that feed Stream B's student dashboard — make sure the profile screen fires that RPC once the new layout lands.

**Done when**
- Every §2.3 field is editable and displayed
- Someone can leave a written recommendation that appears on the recipient's profile
- Skill endorsements are visible and attributable on a profile
- A user can hide individual profile sections from specific audiences
- A business account has a company profile with the required fields

---

### Stream D — Identity, Verification & Media Pipeline

**Branch:** `feat/identity-media` · split from the old Stream C

Split out on purpose. The old Stream C bundled this with fifteen form
fields, but these two items are low-volume and high-risk — a
research-and-design problem plus an infrastructure spike — and they get
buried if a person is also grinding through profile CRUD. Start both in
week one; neither is predictable.

**Requirements**
- §2.1 — **Alumni authentication and identity verification** — "a deliberate design challenge; there is no prescribed solution," but it must be researched, reasoned, and working, not left as a gap
- §2.1 — Accept `@my.aaa.ac.za` and `@aaa.ac.za` student domains alongside the richfield ones
- §2.8 — Video upload with compression/transcoding and thumbnail generation before storage

**Owns**
```
lib/features/auth/signup_screen.dart      (alumni flow)
lib/core/constants.dart                   (isValidStudentEmail — fix domains day one)
lib/data/storage_repository.dart
lib/features/feed/create_post_screen.dart (video upload path only)
supabase/functions/**                     (new — video transcoding)
supabase/migrations/0006_*.sql            (alumni verification docs/status, video job metadata)
```

**Watch out** — Alumni auth is the trap. Right now alumni are just ordinary
pending accounts, which is precisely the gap the brief calls out by name.
Student number + graduation year + document upload + admin verification is a
reasonable starting point, but whatever you pick, write the reasoning down —
it has to be defended live in the presentation. Video can't be done
client-side — it needs a Supabase Edge Function running ffmpeg, or an
external service (Mux, Cloudinary). "Raw, unprocessed video uploads dumped
directly to storage are not acceptable."

**Coordinate with Stream E** — Stream D owns the verification data and the
storage/status backend; Stream E owns `admin_screen.dart`, so the actual
"review this alumnus's documents and approve" UI lands in their Accounts tab,
reading Stream D's schema. Land the migration first and hand them the shape.

**Done when**
- An alumnus can register and be verified through a documented, working flow
- Both AAA student domains are accepted at signup
- A student can post a video that is transcoded and has a generated thumbnail

---

### Stream E — Admin Panel, Platform Ops & Presentation

**Branch:** `feat/admin-ops` · new — assigned to the no-Android-Studio person

New stream, and deliberately shaped for the team member whose machine can't
run Android Studio. The guidelines explicitly allow the admin panel to be "a
separate web-based or desktop management interface" — build it as Flutter
web (`flutter run -d chrome`), which needs only the Flutter SDK and a
browser, no emulator or Android SDK. Building the admin panel means touching
every role's data, which also makes this person the natural one to hold the
whole system in their head for the demo and the deck.

**Requirements**
- §2.2 — Admin panel completion: event management (create/edit/publish institutional events — currently missing entirely), opportunity oversight (approve/remove listings before they're visible), user management and content moderation (Accounts/Flags tabs exist, verify they're complete)
- §2.8 — Real-time notifications audit — confirm connection requests, new messages, opportunity matches, admin announcements, and post activity all trigger a Realtime event, not just messages/DMs
- §2.5 — Event listings feed and programme-relevant event notifications; opportunity apply/track flow for students; confirm smart job matching fires on opportunity approval
- §2.4 — Connection request accept/decline/manage UI, if not already complete

**Owns**
```
lib/features/admin/admin_screen.dart  (Accounts, Listings, Flags tabs + new Events tab — Overview stays Stream B's)
lib/features/events/**
lib/features/notifications/**
lib/data/admin_repository.dart        (moderation/event/opportunity RPCs — not the analytics half)
supabase/migrations/0007_*.sql        (event creation policy, notification trigger gaps)
```

**Watch out** — `admin_screen.dart` is shared with Stream B — Stream E owns
three tabs and a new fourth, Stream B owns Overview. Don't reorder the
`TabBarView` children list; append. The realtime audit is boring but
load-bearing: it's easy to build messages and call the notification
requirement done, then discover at Checkpoint 2 that opportunity matches and
admin announcements never fire an in-app alert.

**Also owns — not code**
- POPIA compliance research and the deck slide — the app stores CVs, alumni verification documents, and student data
- README, setup instructions, and the architecture diagram
- Assembling the 15+ slide deck from what each stream hands over
- Demo script and rehearsal — seeded accounts for all four roles, a run-through that doesn't crash

**Done when**
- An admin can create, edit, and publish institutional events
- An admin can approve or remove an opportunity listing before it's visible to students
- Every listed notification trigger actually fires an in-app alert, verified one by one
- The deck exists in draft with every required section, updated as streams land

---

## 3. Shared-file protocol

Five branches touching one file is where this goes wrong faster than with
three. Extends the rules in `WORKPLAN.md` — everything else in the ownership
lists above belongs to exactly one stream; message the owner before editing
their file.

| File | Rule |
| --- | --- |
| `pubspec.yaml` | Add your dep, commit that line alone, push same day. Never reformat. |
| `lib/core/router.dart` | Add routes at the end of the list. Never reorder existing entries. |
| `lib/providers.dart` | Add providers at the end of your feature's section. Never reorder. |
| `lib/features/admin/admin_screen.dart` | **New rule.** Stream B owns the Overview tab body; Stream E owns Accounts/Listings/Flags and adds Events. Append tabs to the end of the `TabBarView` list — never reorder or touch each other's tab body. |
| `supabase/migrations/` | Never edit an existing migration. Per-stream numbers: A→0003, B→0004, C→0005, D→0006, E→0007. Further migrations: `0008_a_*`, `0009_b_*` etc. with your stream letter. |

---

## 4. How the streams fit together

No stream is fully self-contained. These are the six points where one
stream's output is another's input — worth a two-minute sync rather than
discovering at Checkpoint 2.

- **C → A** produces the skills list shape and profile-completeness
  definition. A's assistant reads both to give context-aware feedback and to
  accept CV-extracted skills — agree on the schema before A builds the
  accept/reject UI.
- **C → B** produces the expanded profile fields that "completeness vs.
  programme peers" is computed from, on the student dashboard. B's
  completeness metric is wrong until C's fields exist.
- **C → E** calls a profile-view RPC that must fire from the profile screen
  for B's "profile views over time" chart to have data. C wires the call
  once E/B define the RPC name.
- **D → E** hands off the alumni verification schema — E builds the
  admin-side review UI (approve/reject a submitted document) inside the
  Accounts tab it already owns, reading D's tables. D lands the migration
  first.
- **E → B** approves into opportunity approval events that feed B's
  "business approval pipeline" admin metric and should trigger the existing
  `matched_opportunities()` smart-matching function — E verifies the
  trigger, B charts the result.
- **D → feed UI**: D owns the video transcoding backend but only the upload
  path inside `create_post_screen.dart` — the rest of the feed UI stays
  untouched by D.

---

## 5. Fallback — four streams

If splitting C into C + D reads as more coordination than it's worth,
collapse them back into one profiles-and-identity stream — the original
`WORKPLAN.md` shape — and use the fifth person as a floating helper instead
of a fifth owner.

| Stream | Who |
| --- | --- |
| A — AI, Onboarding & Assistant | 1 person, solo |
| B — Analytics, Dashboards & Feed | Current owner + the floater, split by dashboard as above |
| C — Profiles, Media & Identity (original scope) | 1 person, solo |
| E — Admin Panel, Ops & Presentation | The no-Android-Studio person |

Weaker than the 5-stream version specifically where it matters most: Stream
C reabsorbs the alumni-auth research and the video pipeline alongside
fifteen profile fields, which is the combination `WORKPLAN.md` itself
flagged as needing a split if that person needs help. Use this shape only if
the floater is committed to B early and often, not as a way to avoid naming
a fifth owner.

---

## 6. Timeline

| When | Milestone |
| --- | --- |
| Day 1 | AAA email domains fixed and merged — Stream D, minutes of work against a mandatory clause, do it before anything else lands on that branch. |
| Wk 1 | A: Gemini talking to the app · B: student dashboard · C: profile schema + new fields · D: alumni-auth design doc + video spike · E: admin web build stood up, Events tab scaffolded |
| Checkpoint 1 | Every stream has one thing merged to main. |
| Wk 2 | A: assistant + tutorial · B: business + admin dashboards · C: recommendations, visibility, remaining fields · D: alumni flow working end to end · E: notification audit, opportunity oversight, deck skeleton |
| Checkpoint 2 | Walk guidelines §2 as a checklist, together. Anything not started gets cut or triaged here — three days from freeze is the last point where cutting scope is a decision, not an accident. |
| Wk 3 | A: CV parsing · B: pathways + feed ranking · C: polish · D: video pipeline finished · E: deck finished, demo script written |
| 12 Sep | Code freeze. Only bug fixes after this. |
| 13–14 Sep | Integration testing, demo rehearsal with all five roles present, deck finalised. |
| 15–16 Sep | Campus round. All five present a portion — the brief requires it. |

---

## 7. Still to confirm with the coordinator

- Registration deadline was 21 August 2026 — confirm the team is actually registered
- Team size: guidelines say 7–10, the invitation letter says 5 — which one governs marking

---

Derived from `CLAUDE.md`, `WORKPLAN.md`, `docs/2026 Hackathon Guidelines .pdf`
and `docs/Project Break Down.pdf`. Branches `ai-assistant`,
`analytics-dashboards` and `profiles-media` already exist on origin with no
commits ahead of main — all five streams are starting from the same blank
slate.
