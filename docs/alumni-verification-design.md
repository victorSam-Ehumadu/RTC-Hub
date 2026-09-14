# Alumni identity verification — design reasoning

Guidelines §2.1 calls this out by name as "a deliberate design challenge;
there is no prescribed solution," but requires it to be "addressed with a
researched, reasoned solution, not left as a gap." This document is that
reasoning, written down so it can be defended live in the presentation.

## Why this is hard

Every other role has something the platform can check automatically:

- **Students** have a live institutional email (`@my.richfield.ac.za` /
  `@my.aaa.ac.za`) with a 9-digit student number baked into the address. The
  domain and the prefix are both checked in `handle_new_user()` — see
  `docs/stream-redistribution.md`, Stream D item 1.
- **Businesses** are already expected to go through manual admin review —
  there's no institutional signal to check either, but the brief doesn't
  demand one.

Alumni have neither. They've graduated, so a Richfield email address is
gone or about to be deactivated, and there's no database of past student
records in this system to check a claimed student number against — the app
never had one; it's a fresh Supabase project, not a copy of the college's
actual student information system.

## The options considered

1. **Trust the claim outright** (no document, just self-reported student
   number + graduation year, same as students get auto-ACTIVE). Rejected —
   this is exactly the gap the brief calls out by name: anyone could tick
   "Alumni" and claim any graduation year with zero friction.
2. **An institution-issued verification code**, distributed by Richfield to
   real alumni (e.g. via their alumni association mailing list) and checked
   against a table at signup. Rejected for this submission: it requires a
   real distribution channel and a pre-populated code list that don't exist,
   and can't be fabricated convincingly for a hackathon demo without it
   *looking* fabricated.
3. **Self-declared claim, cross-checked against our own data, with an
   optional document as a human admin's fallback evidence** (chosen — see
   below).

## What actually got built, and why

Two checks, in order, not one:

**First, an automatic cross-check against RTC Hub's own data.** At signup,
`handle_new_user()` looks for an existing `profiles` row with `role =
'STUDENT'` whose student number and faculty match what the alumnus just
claimed. If one exists, the account is approved immediately (`ACTIVE`, not
`PENDING`) — the reasoning being that the matched STUDENT row was itself
already verified by the institutional email domain check (§2.1, Stream D
item 1), so an alumnus who studied here under that number inherits that
trust. This only fires for someone who used RTC Hub as a verified student
before graduating; a brand-new alumnus with no prior footprint in this
database will never match, which is the expected common case for a fresh
hackathon submission with no pre-existing user base.

**This auto-check is explicitly not a security guarantee, and that's
stated on purpose rather than hidden:** a student number is not a secret.
Anyone who knows or guesses a real student's number and faculty could
claim to be that student's future alumnus and get auto-approved. It is a
*convenience for returning users*, not proof of identity. Accepting that
trade-off is deliberate: the alternative (requiring proof for every alumnus
regardless of history with the platform) adds friction for zero benefit to
the one population — returning users — where the platform already has a
verified signal to lean on.

**Second, for everyone the auto-check doesn't match, an optional document
+ manual admin review.** The alumnus can upload a document — degree
certificate, graduation letter, or old student card — to the private
`verification` storage bucket from the pending-account screen at any time
before an admin looks at their account. Uploading is *optional, not
required*: someone without a scanned document handy shouldn't be blocked
from registering at all; the admin instead makes a judgment call from
whatever's available — the claimed student number/graduation year alone,
or those plus a document if one was provided. This is the same trust model
most real institutions use for manual document review, just without
OCR/fraud-detection tooling behind it, which is a fair and explicit scope
cut for a hackathon prototype. A sufficiently convincing forged document
would get past a human reviewer either way — that limitation exists
regardless of whether the upload is required or optional, so making it
optional costs nothing in the case it doesn't cover.

The mitigations that do exist for the manual-review path:
- The account cannot act on the platform at all while `PENDING` — no
  Logic Points, no messaging, no bounty payouts — so a rejected or
  never-reviewed fake account costs an attacker nothing to attempt but
  gains them nothing either.
- The document, when provided, sits in a **private** storage bucket
  (`verification`), not public — only the account owner and an admin (via
  `SECURITY DEFINER` admin RPCs / storage policies) can read it, per the
  RLS model in `CLAUDE.md`.
- Nothing about either path is trusted implicitly by the client — the
  auto-match runs inside `handle_new_user()`, a `SECURITY DEFINER` trigger
  the client cannot influence beyond the claim it submits, and manual-review
  `status` stays `PENDING` until an admin explicitly flips it, the same
  `trg_profiles_guard`-protected mechanism used for business approval.

## What actually got built

- `profiles.student_number`, `graduation_year`, `verification_photo_url` —
  pre-existing columns, previously dead (nothing populated them for alumni)
- Signup screen (`signup_screen.dart`) collects the claimed student number
  and graduation year for the `ALUMNI` role — these are still required
  inputs (the claim itself, not the document) so there's always something
  for the auto-match or a human admin to work from
- `handle_new_user()` (migration `0010_d_alumni_verification.sql`,
  superseding the version in `0006_d_aaa_domains.sql`) runs the auto-match:
  an `ALUMNI` signup whose student number + faculty matches an existing
  `STUDENT` profile is set `ACTIVE` immediately; everyone else is `PENDING`,
  same as before
- The optional document is uploaded **after** signup completes, from
  `AccountGateScreen` (the screen a `PENDING` account already lands on) —
  not as a second step on the signup screen. The router redirects away from
  `/signup` the instant a session exists (see `router.dart`'s `redirect`),
  so there's no window to run a second step there; uploading from the
  pending-account screen also means the alumnus can retry if their first
  document was the wrong file, without re-registering, or skip it entirely
- `StorageRepository.uploadVerification()` (pre-existing, previously
  unused) handles the actual upload to the private bucket

## What Stream E needs to build next

The admin "Accounts" tab currently lists `PENDING` users with generic
Approve/Reject buttons and no way to see *why* an alumnus is trustworthy —
and by design, only the alumni the auto-match couldn't place ever reach
that tab at all. The shape is ready for Stream E to build against:
`profile.studentNumber`, `profile.graduationYear`,
`profile.verificationPhotoUrl` (a signed URL into the private bucket,
viewable directly, and possibly absent — the upload is optional, so the UI
needs a sensible "no document provided" state, not just a broken image).
Stream E's job is surfacing those three fields — and ideally a way to open
the document when one exists — on each pending alumnus's card before the
admin decides.
