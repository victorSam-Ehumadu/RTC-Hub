-- ============================================================
-- RTC Hub — 0019: revert faculty segregation on posts/opportunities/events
--
-- `origin/fix/backend-access` (unmerged, its own `0007_faculty_segregation.sql`
-- — numbering from a different snapshot of this repo, unrelated to our own
-- 0007_b_dashboard_signals.sql) has already been run against this *shared*
-- Supabase project, even though its branch was never merged. It rewrote
-- posts_select / opps_select / events_select to only show a row when its
-- faculty is NULL or matches the viewer's `my_interests()`. That is why a
-- STUDENT with faculty = BUSINESS sees only BUSINESS-faculty posts in both
-- Following and Discover: PostRepository.feed()/discover() never filter on
-- faculty, so the rows are being dropped by RLS underneath them, not by any
-- code in this branch.
--
-- This is a real, deliberately-designed feature on that branch (see its own
-- comments — it is not a mistake), but it is not documented in CLAUDE.md, this
-- branch's PostRepository has no idea it exists, and applying it to the
-- shared project ahead of a merge broke every other stream's testing. Revert
-- the enforcement here; leave the data model it introduced alone so the
-- feature can be re-enabled later without a backfill:
--
--   * `profiles.content_interests`, `posts.faculty`, `events.faculty` stay,
--     and `trg_profiles_interests` / `trg_posts_faculty` keep populating them
--     — harmless metadata as long as nothing reads it for access control.
--   * `feed_post_ids()`, `ranked_feed()`, `my_interests()`, the rebalanced
--     `matched_opportunities()` and the faculty-aware `on_opportunity_activated()`
--     are untouched: none of them are called from this branch's Dart, and none
--     of them gate what a client can read — only the three SELECT policies
--     below did that.
--
-- Talk to whoever owns fix/backend-access before this lands — they may want
-- to bring the feature back properly once it's actually merged and the app
-- code (this branch's PostRepository included) is updated to match it.
--
-- Run after 0018_profile_campus_enrollment.sql.
-- ============================================================

-- Posts: back to "not flagged, or yours, or you're an admin" — no faculty term.
DROP POLICY IF EXISTS "posts_select" ON posts;
CREATE POLICY "posts_select" ON posts FOR SELECT USING (
  is_flagged = FALSE OR author_id = auth.uid() OR is_admin()
);

-- Opportunities: back to the 0001 policy, no faculty term.
DROP POLICY IF EXISTS "opps_select" ON opportunities;
CREATE POLICY "opps_select" ON opportunities FOR SELECT USING (
  status = 'ACTIVE' OR business_id = auth.uid() OR is_admin()
);

-- Events: back to the 0001 policy. This also drops the target_roles check
-- fix/backend-access bundled in alongside the faculty one — target_roles
-- enforcement is a legitimate, separate idea (0001 defined the column but
-- 0001's own events_select never read it), just not what this migration is
-- about. Worth re-adding on its own if the team wants it.
DROP POLICY IF EXISTS "events_select" ON events;
CREATE POLICY "events_select" ON events FOR SELECT USING (TRUE);
