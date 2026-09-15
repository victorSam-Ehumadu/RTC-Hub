# Stream D handoff

Stream D (`feat/identity-media`) needs a new owner — the person working it is
leaving the team. This is the honest state of things as of the handoff, so
whoever picks this up isn't rediscovering it from scratch.

## Item 1 — AAA student email domains

**Code: done.** `isValidStudentEmail` (Dart) and `handle_new_user()` (SQL,
migrations `0006` then `0010`) both accept `@my.richfield.ac.za`,
`@richfield.ac.za`, `@my.aaa.ac.za`, `@aaa.ac.za`, all requiring a 9-digit
prefix.

**Tested:**
- Real signup with `@my.richfield.ac.za` — **works end-to-end**, confirmed
  on a physical device
- The domain-matching logic itself, in isolation (a standalone Dart script
  running `isValidStudentEmail` against all four domains plus two invalid
  cases, and a plain SQL `SELECT ... LIKE` check on the same patterns) —
  **all pass**

**Not tested, and can't be right now:** a real signup with `@aaa.ac.za` or
`@my.aaa.ac.za`. Confirmed via direct DNS lookup (`nslookup`) that **neither
domain resolves** — "Non-existent domain," compared against
`richfield.ac.za` which resolves cleanly to a real server. This is not a bug
in this code. The guidelines PDF was checked directly and does literally
specify these exact domains, so there's no typo on our end either.

**Open question for the coordinator, unresolved:** what is the actual, real
domain for the AAA partner campus? Until that's answered, the requirement
can't be demonstrated live with a genuine `aaa.ac.za` address — Supabase's
Auth backend refuses to send to a domain with no DNS records at all, which
likely also explains some of the "email address invalid" errors hit during
testing (see the rate-limit note below — the two may be related). Whoever
inherits this should chase that answer down, then it's a one-line change in
`kStudentEmailDomains` (`lib/core/constants.dart`) and the `LIKE` list in
`handle_new_user()`.

## Item 2 — Alumni verification

**Code: done.** Design reasoning is in
`docs/alumni-verification-design.md` — read that first, it explains the
auto-match logic and its honest limitation (student numbers aren't secret).
Summary: an `ALUMNI` signup whose claimed student number + faculty matches
an existing `STUDENT` profile auto-approves to `ACTIVE`
(`handle_new_user()`, migration `0010`); everyone else stays `PENDING`, with
an *optional* document upload on `AccountGateScreen`.

**Tested:** nothing conclusively. Every attempt to run the designed test
(sign up Student → sign up Alumni with matching number/faculty → check
`profiles` via SQL) hit Supabase's default-mailer rate limit before
completing. **The auto-match logic has never been confirmed working
end-to-end** — it's implemented and the isolated logic looks right by
inspection, but nobody has actually seen it produce an `ACTIVE` alumni
account. Don't take "it probably works" as settled; it needs an actual run.

**Also never tested:** the document-upload button on `AccountGateScreen`
(`_AlumniVerificationUpload` in `app_shell.dart`) — untested UI/storage
path, separate from the auto-match logic above.

## Item 3 — Video upload pipeline

**Not started at all.** No media/video UI in `create_post_screen.dart`, no
`supabase/functions/` directory, no migration. See
`docs/stream-redistribution.md`'s Stream D section for the original scope:
compression/transcoding + thumbnail generation before storage, "raw
unprocessed video uploads... not acceptable" per the guidelines.
`StorageRepository.uploadPostMedia()` exists but is unused — nothing calls
it yet.

## The recurring blocker worth fixing first

Supabase's project has **"Confirm email" turned on**, locked to
Admin/Owner-only permissions (the account used for this work only had
Developer access, so it was never able to fix it directly). This has
repeatedly blocked testing throughout — both the rate-limit hits above and,
plausibly, the AAA domain rejection. Whoever continues this should either
get an admin to turn it off, or set up custom SMTP (Authentication → Emails)
to raise the default mailer's very low send limit. Until that's resolved,
expect the same wall on any further testing.

## Local-only, not committed

`android/gradle/wrapper/gradle-wrapper.properties` was bumped locally from
Gradle 8.14 to 9.1.0 to fix a Java 25 incompatibility that blocked Android
builds entirely on this machine. Deliberately **not** included in any
Stream D commit — it's unrelated infrastructure, and there's already a
`chore/gradle-wrapper` branch on origin (though it turned out to be about
committing the wrapper scripts to git, not the version bump — this specific
fix still needs to land somewhere for the team, on its own branch).
