-- ============================================================
-- RTC Hub — 0013 (Stream B): business analytics dashboard (§2.7)
--
-- §2.7, literally: "total applicant pipeline per posted opportunity,
-- engagement rate on job listings, candidate skill distribution across
-- Richfield programmes, demographic breakdown of applicants by programme
-- and year of study, and overall reach and visibility statistics for the
-- company profile."
--
-- Company profile reach needs no new function — a business's own
-- `profile_analytics.profile_views` already accumulates via
-- record_profile_view() (0002), fired from ProfileScreen on every visit,
-- business profiles included. AnalyticsRepository.forBusiness() reads that
-- table exactly like forStudent() already does.
--
-- Everything below is invoker-rights `LANGUAGE sql STABLE`, not
-- SECURITY DEFINER, with one deliberate exception. That matters here more
-- than in 0009: §2.1 says a business "may not access student-only content
-- or personal information beyond what a student has explicitly made
-- visible", and profiles_select (0003) is exactly where that's enforced
-- (`CASE WHEN my_role() = 'BUSINESS' THEN visibility_business`). Running
-- these as SECURITY DEFINER would bypass that check and hand a recruiter
-- applicants who opted out — the opposite of what 0009's admin functions
-- correctly do for a different reason (admins are allowed to see
-- everything). apps_select already grants a business owner its own
-- opportunity_applications rows, and skills_select_public is USING (TRUE),
-- so invoker rights alone gets every read below the access it needs.
--
-- One consequence of that choice, worth stating plainly: applying to a
-- listing does not override visibility_business. A candidate who has
-- turned off business visibility still applies successfully (apps_insert_own
-- only checks applicant_id = auth.uid()) but disappears from the
-- programme/skill breakdowns below, because the invoker-rights join to
-- profiles silently drops rows RLS won't show the caller. So
-- business_listing_pipeline()'s applicant_count (counted straight off
-- opportunity_applications, no profiles join) can legitimately be larger
-- than the sum of business_applicant_demographics(). That is not a bug —
-- it is the same access boundary the rest of the app relies on — but the
-- UI must say so next to those two charts rather than let the numbers look
-- inconsistent unexplained.
--
-- Run after 0009_b_admin_dashboard.sql.
-- ============================================================

-- ─── LISTING REACH (views) ────────────────────────────────────
-- Engagement rate has no denominator today — nothing tracks that a listing
-- was ever seen. This is the opportunity-side equivalent of profile_views:
-- a dedup'd-per-day count of distinct viewers, written only through
-- record_opportunity_views() below, same shape as skill_search_counts
-- (0007) and profile_analytics (0001/0002) — no client INSERT policy at
-- all, only a SECURITY DEFINER writer.
CREATE TABLE opportunity_views (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  opportunity_id UUID NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  viewer_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  viewed_on      DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(opportunity_id, viewer_id, viewed_on)
);

ALTER TABLE opportunity_views ENABLE ROW LEVEL SECURITY;

-- Only the owning business (or an admin) can read who viewed their
-- listings — mirrors apps_select's "owns the opportunity" shape. Aggregate
-- functions below only ever return counts, never viewer_id rows, so this
-- table's raw contents are never exposed beyond that owner regardless.
CREATE POLICY "opportunity_views_select_owner" ON opportunity_views FOR SELECT USING (
  is_admin()
  OR EXISTS (SELECT 1 FROM opportunities o WHERE o.id = opportunity_id AND o.business_id = auth.uid())
);

-- Fire-and-forget from OpportunityRepository.browse()/matched() (Dart), one
-- call per page load with every listing id on screen — not one call per
-- card — so scrolling a list of 20 listings is one round trip, not 20.
-- SECURITY DEFINER because the viewer is, by definition, not the listing's
-- owner (same reason record_profile_view() needs it). Guarded two ways:
-- my_role() restricts this to STUDENT/ALUMNI (the population a job listing
-- actually targets — an admin's own moderation browsing shouldn't count
-- as "reach"), and business_id <> auth.uid() drops a business's own
-- listings from its own view count, mirroring record_profile_view()'s
-- self-view guard.
CREATE OR REPLACE FUNCTION record_opportunity_views(p_ids UUID[])
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN RETURN; END IF;
  IF my_role() NOT IN ('STUDENT', 'ALUMNI') THEN RETURN; END IF;

  INSERT INTO opportunity_views (opportunity_id, viewer_id, viewed_on)
  SELECT o.id, auth.uid(), CURRENT_DATE
  FROM opportunities o
  WHERE o.id = ANY(p_ids) AND o.business_id <> auth.uid()
  ON CONFLICT (opportunity_id, viewer_id, viewed_on) DO NOTHING;
END;
$fn$;

GRANT EXECUTE ON FUNCTION record_opportunity_views(UUID[]) TO authenticated;

-- ─── APPLICANT PIPELINE PER LISTING (+ engagement rate) ───────
-- One row per listing the caller owns, PENDING/REJECTED included — a
-- business should see its whole funnel, not just what's currently live.
-- `reach` is distinct viewers (see above); the Dart layer turns
-- applicant_count/reach into the engagement-rate percentage so a PENDING
-- listing (reach always 0, since opps_select never shows it to a student
-- to view) can be labelled "awaiting views" instead of a misleading 0%.
CREATE OR REPLACE FUNCTION business_listing_pipeline()
RETURNS TABLE(opportunity_id UUID, title TEXT, status TEXT, applicant_count BIGINT, reach BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT o.id, o.title, o.status::TEXT,
         COUNT(DISTINCT a.applicant_id),
         COUNT(DISTINCT v.viewer_id)
  FROM opportunities o
  LEFT JOIN opportunity_applications a ON a.opportunity_id = o.id
  LEFT JOIN opportunity_views v ON v.opportunity_id = o.id
  WHERE o.business_id = auth.uid()
  GROUP BY o.id, o.title, o.status
  ORDER BY o.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION business_listing_pipeline() TO authenticated;

-- ─── CANDIDATE SKILL DISTRIBUTION ACROSS PROGRAMMES ───────────
-- Every other bullet in §2.7's business list is possessive ("per posted
-- opportunity", "on job listings", "of applicants", "for the company
-- profile") and this one says "candidate", not "student" — so this is
-- scoped to the caller's own applicant pool, not the whole platform (that
-- would be top_wanted_skills()'s job, already built for the student
-- dashboard in 0007, and it answers a different question: what businesses
-- ask for, not who actually applied).
--
-- "Distribution... across Richfield programmes" is taken as a genuine
-- skill × programme cross-tab, not a flat skill count: for each of the
-- caller's top skills-in-demand-among-applicants, top_course names the
-- programme that skill is most common in among those applicants. A
-- business with only a handful of applicants still gets a sensible
-- single-programme answer per skill rather than an empty or noisy matrix —
-- the shape degrades gracefully instead of needing a minimum sample size.
CREATE OR REPLACE FUNCTION business_applicant_skill_distribution(p_limit INT DEFAULT 8)
RETURNS TABLE(skill TEXT, total BIGINT, top_course TEXT)
LANGUAGE sql STABLE AS $$
  WITH by_skill_course AS (
    SELECT s.name AS skill,
           COALESCE(p.course, 'Unspecified') AS course,
           COUNT(DISTINCT a.applicant_id) AS n
    FROM opportunity_applications a
    JOIN opportunities o ON o.id = a.opportunity_id
    JOIN profiles p ON p.id = a.applicant_id
    JOIN skills s ON s.user_id = a.applicant_id
    WHERE o.business_id = auth.uid()
    GROUP BY s.name, p.course
  ),
  totals AS (
    SELECT skill, SUM(n) AS total FROM by_skill_course GROUP BY skill
  ),
  ranked AS (
    SELECT skill, course, n,
           ROW_NUMBER() OVER (PARTITION BY skill ORDER BY n DESC, course) AS rn
    FROM by_skill_course
  )
  SELECT t.skill, t.total, r.course
  FROM totals t
  JOIN ranked r ON r.skill = t.skill AND r.rn = 1
  ORDER BY t.total DESC, t.skill
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION business_applicant_skill_distribution(INT) TO authenticated;

-- ─── APPLICANT DEMOGRAPHIC BREAKDOWN (programme + year) ───────
-- COUNT(DISTINCT applicant_id): an applicant who has applied to more than
-- one of the caller's listings must not be counted once per application —
-- this is "how many applicants", not "how many applications".
CREATE OR REPLACE FUNCTION business_applicant_demographics()
RETURNS TABLE(course TEXT, academic_year TEXT, total BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(p.course, 'Unspecified'),
         COALESCE(p.academic_year, 'Unspecified'),
         COUNT(DISTINCT a.applicant_id)
  FROM opportunity_applications a
  JOIN opportunities o ON o.id = a.opportunity_id
  JOIN profiles p ON p.id = a.applicant_id
  WHERE o.business_id = auth.uid()
  GROUP BY p.course, p.academic_year
  ORDER BY COUNT(DISTINCT a.applicant_id) DESC, p.course;
$$;

GRANT EXECUTE ON FUNCTION business_applicant_demographics() TO authenticated;

-- VERIFY BEFORE DEMOING: business_applicant_skill_distribution() and
-- business_applicant_demographics() both join through profiles, so their
-- totals can legitimately be lower than business_listing_pipeline()'s
-- applicant_count whenever an applicant has visibility_business = FALSE
-- (see the header note above). Confirm the dashboard screen labels those
-- two sections as "applicants visible to your business profile" rather
-- than presenting them as the full pipeline restated.
