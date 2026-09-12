-- ============================================================
-- RTC Hub — 0012: the business and administrator dashboards (§2.7)
--
-- §2.7 asks for three distinct dashboards, one per user type, and says
-- plainly that "a single generic statistics page shared across user types
-- will not satisfy this requirement" and that "raw numbers displayed without
-- visualisation will not satisfy this requirement" either.
--
-- Stream B built the student dashboard. This migration supplies the data for
-- the other two. Every function returns a shape a chart can consume directly
-- — a series of labelled points, or a breakdown — rather than a single
-- number, because the screens have to plot, not print.
--
-- All of these are SECURITY DEFINER with an explicit role check inside. They
-- aggregate across rows the caller cannot read individually: a business may
-- not read another applicant's profile, but it is entitled to know that four
-- of its applicants are third-years. Doing it as SECURITY INVOKER would
-- return a chart silently missing everyone the caller cannot see, which is
-- worse than refusing.
--
-- Run after 0011_profiles_recommendations_saves.sql.
-- ============================================================


-- ─── BUSINESS DASHBOARD ──────────────────────────────────────

-- Applicant pipeline per listing: the headline number a recruiter opens the
-- app for. Includes listings with zero applicants, which a join would drop —
-- "nobody applied" is the most actionable bar on the chart.
CREATE OR REPLACE FUNCTION business_pipeline()
RETURNS TABLE (
  opportunity_id UUID,
  title          TEXT,
  status         account_status,
  applicants     INT,
  shortlisted    INT,
  rejected       INT,
  posted_at      TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT o.id,
         o.title,
         o.status,
         COUNT(a.id)::INT,
         COUNT(a.id) FILTER (WHERE a.status = 'SHORTLISTED')::INT,
         COUNT(a.id) FILTER (WHERE a.status = 'REJECTED')::INT,
         o.created_at
    FROM opportunities o
    LEFT JOIN opportunity_applications a ON a.opportunity_id = o.id
   WHERE o.business_id = auth.uid()
   GROUP BY o.id, o.title, o.status, o.created_at
   ORDER BY o.created_at DESC;
$fn$;

GRANT EXECUTE ON FUNCTION business_pipeline() TO authenticated;

-- Candidate skill distribution across Richfield programmes, plus the
-- programme/year breakdown §2.7 asks for by name.
CREATE OR REPLACE FUNCTION business_candidate_mix()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE result JSONB;
BEGIN
  IF my_role() IS DISTINCT FROM 'BUSINESS' AND NOT is_admin() THEN
    RAISE EXCEPTION 'Business accounts only';
  END IF;

  WITH mine AS (
    SELECT a.applicant_id
      FROM opportunity_applications a
      JOIN opportunities o ON o.id = a.opportunity_id
     WHERE o.business_id = auth.uid()
  )
  SELECT JSONB_BUILD_OBJECT(
    'by_programme', COALESCE((
      SELECT JSONB_AGG(x) FROM (
        SELECT COALESCE(p.course, 'Unspecified') AS label, COUNT(*)::INT AS value
          FROM mine m JOIN profiles p ON p.id = m.applicant_id
         GROUP BY 1 ORDER BY 2 DESC LIMIT 8
      ) x), '[]'::JSONB),

    'by_year', COALESCE((
      SELECT JSONB_AGG(x) FROM (
        SELECT COALESCE(p.academic_year, 'Unspecified') AS label, COUNT(*)::INT AS value
          FROM mine m JOIN profiles p ON p.id = m.applicant_id
         GROUP BY 1 ORDER BY 1
      ) x), '[]'::JSONB),

    'by_faculty', COALESCE((
      SELECT JSONB_AGG(x) FROM (
        SELECT COALESCE(p.faculty::TEXT, 'Unspecified') AS label, COUNT(*)::INT AS value
          FROM mine m JOIN profiles p ON p.id = m.applicant_id
         GROUP BY 1 ORDER BY 2 DESC
      ) x), '[]'::JSONB),

    -- What the applicant pool can actually do, which is the question behind
    -- "should we keep advertising this role".
    'top_skills', COALESCE((
      SELECT JSONB_AGG(x) FROM (
        SELECT s.name AS label, COUNT(*)::INT AS value
          FROM mine m JOIN skills s ON s.user_id = m.applicant_id
         GROUP BY 1 ORDER BY 2 DESC LIMIT 10
      ) x), '[]'::JSONB),

    'total_applicants', (SELECT COUNT(DISTINCT applicant_id)::INT FROM mine)
  ) INTO result;

  RETURN result;
END;
$fn$;

GRANT EXECUTE ON FUNCTION business_candidate_mix() TO authenticated;

-- Listing engagement and company profile reach over time. One series the
-- screen can plot as a line rather than two numbers it has to caption.
CREATE OR REPLACE FUNCTION business_reach(p_days INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE result JSONB;
BEGIN
  IF my_role() IS DISTINCT FROM 'BUSINESS' AND NOT is_admin() THEN
    RAISE EXCEPTION 'Business accounts only';
  END IF;

  SELECT JSONB_BUILD_OBJECT(
    -- A continuous date spine, so a day with no applications plots as zero
    -- instead of the line hopping over it and implying activity.
    'applications_by_day', COALESCE((
      SELECT JSONB_AGG(x ORDER BY x->>'label') FROM (
        SELECT JSONB_BUILD_OBJECT(
                 'label', TO_CHAR(d.day, 'YYYY-MM-DD'),
                 'value', COUNT(a.id)::INT
               ) AS x
          FROM GENERATE_SERIES(CURRENT_DATE - (p_days - 1), CURRENT_DATE, '1 day') AS d(day)
          LEFT JOIN opportunity_applications a
                 ON a.created_at::DATE = d.day
                AND a.opportunity_id IN (
                      SELECT id FROM opportunities WHERE business_id = auth.uid())
         GROUP BY d.day
      ) s), '[]'::JSONB),

    'profile_views_by_day', COALESCE((
      SELECT JSONB_AGG(x ORDER BY x->>'label') FROM (
        SELECT JSONB_BUILD_OBJECT(
                 'label', TO_CHAR(d.day, 'YYYY-MM-DD'),
                 'value', COALESCE(SUM(pa.profile_views), 0)::INT
               ) AS x
          FROM GENERATE_SERIES(CURRENT_DATE - (p_days - 1), CURRENT_DATE, '1 day') AS d(day)
          LEFT JOIN profile_analytics pa
                 ON pa.date = d.day AND pa.user_id = auth.uid()
         GROUP BY d.day
      ) s), '[]'::JSONB),

    'active_listings',
      (SELECT COUNT(*)::INT FROM opportunities
        WHERE business_id = auth.uid() AND status = 'ACTIVE'),
    'pending_listings',
      (SELECT COUNT(*)::INT FROM opportunities
        WHERE business_id = auth.uid() AND status = 'PENDING'),

    -- Applications per live listing. The closest honest reading of
    -- "engagement rate" from what the schema records.
    'applications_per_listing', COALESCE((
      SELECT ROUND(
               COUNT(a.id)::NUMERIC
               / GREATEST(COUNT(DISTINCT o.id), 1), 2)
        FROM opportunities o
        LEFT JOIN opportunity_applications a ON a.opportunity_id = o.id
       WHERE o.business_id = auth.uid() AND o.status = 'ACTIVE'), 0)
  ) INTO result;

  RETURN result;
END;
$fn$;

GRANT EXECUTE ON FUNCTION business_reach(INT) TO authenticated;


-- ─── ADMINISTRATOR DASHBOARD ─────────────────────────────────
-- §2.7 names each metric, so each one is here rather than a generic count:
-- users by type, monthly active users, registrations over time, content
-- volume, flagged content, and the business approval pipeline.

CREATE OR REPLACE FUNCTION admin_dashboard(p_days INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE result JSONB;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Administrators only';
  END IF;

  SELECT JSONB_BUILD_OBJECT(
    'users_by_type', COALESCE((
      SELECT JSONB_AGG(x) FROM (
        SELECT role::TEXT AS label, COUNT(*)::INT AS value
          FROM profiles GROUP BY 1 ORDER BY 2 DESC
      ) x), '[]'::JSONB),

    'users_by_status', COALESCE((
      SELECT JSONB_AGG(x) FROM (
        SELECT status::TEXT AS label, COUNT(*)::INT AS value
          FROM profiles GROUP BY 1 ORDER BY 2 DESC
      ) x), '[]'::JSONB),

    'registrations_by_day', COALESCE((
      SELECT JSONB_AGG(x ORDER BY x->>'label') FROM (
        SELECT JSONB_BUILD_OBJECT(
                 'label', TO_CHAR(d.day, 'YYYY-MM-DD'),
                 'value', COUNT(p.id)::INT
               ) AS x
          FROM GENERATE_SERIES(CURRENT_DATE - (p_days - 1), CURRENT_DATE, '1 day') AS d(day)
          LEFT JOIN profiles p ON p.created_at::DATE = d.day
         GROUP BY d.day
      ) s), '[]'::JSONB),

    -- "Monthly active users" has no session table to read, so it is derived
    -- from what the schema does record: anyone who posted, commented,
    -- messaged or reacted in the window. Stated here so the presentation can
    -- describe the metric honestly rather than implying session tracking.
    'monthly_active_users', (
      SELECT COUNT(DISTINCT uid)::INT FROM (
        SELECT author_id AS uid FROM posts    WHERE created_at > NOW() - INTERVAL '30 days'
        UNION SELECT author_id FROM comments  WHERE created_at > NOW() - INTERVAL '30 days'
        UNION SELECT sender_id FROM messages  WHERE created_at > NOW() - INTERVAL '30 days'
        UNION SELECT user_id   FROM post_reactions WHERE created_at > NOW() - INTERVAL '30 days'
      ) active),

    'content_volume', JSONB_BUILD_OBJECT(
      'posts',         (SELECT COUNT(*)::INT FROM posts),
      'videos',        (SELECT COUNT(*)::INT FROM posts WHERE video_url IS NOT NULL),
      'bounties',      (SELECT COUNT(*)::INT FROM posts WHERE is_bounty),
      'comments',      (SELECT COUNT(*)::INT FROM comments),
      'opportunities', (SELECT COUNT(*)::INT FROM opportunities),
      'events',        (SELECT COUNT(*)::INT FROM events)
    ),

    'content_by_day', COALESCE((
      SELECT JSONB_AGG(x ORDER BY x->>'label') FROM (
        SELECT JSONB_BUILD_OBJECT(
                 'label', TO_CHAR(d.day, 'YYYY-MM-DD'),
                 'value', COUNT(p.id)::INT
               ) AS x
          FROM GENERATE_SERIES(CURRENT_DATE - (p_days - 1), CURRENT_DATE, '1 day') AS d(day)
          LEFT JOIN posts p ON p.created_at::DATE = d.day
         GROUP BY d.day
      ) s), '[]'::JSONB),

    'flagged_open',     (SELECT COUNT(*)::INT FROM content_flags WHERE NOT resolved),
    'flagged_resolved', (SELECT COUNT(*)::INT FROM content_flags WHERE resolved),

    -- The business approval pipeline §2.7 asks for by name.
    'business_pipeline', JSONB_BUILD_OBJECT(
      'pending',  (SELECT COUNT(*)::INT FROM profiles WHERE role = 'BUSINESS' AND status = 'PENDING'),
      'active',   (SELECT COUNT(*)::INT FROM profiles WHERE role = 'BUSINESS' AND status = 'ACTIVE'),
      'rejected', (SELECT COUNT(*)::INT FROM profiles WHERE role = 'BUSINESS' AND status = 'REJECTED')
    ),

    'opportunity_pipeline', JSONB_BUILD_OBJECT(
      'pending', (SELECT COUNT(*)::INT FROM opportunities WHERE status = 'PENDING'),
      'active',  (SELECT COUNT(*)::INT FROM opportunities WHERE status = 'ACTIVE'),
      'rejected',(SELECT COUNT(*)::INT FROM opportunities WHERE status = 'REJECTED')
    )
  ) INTO result;

  RETURN result;
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_dashboard(INT) TO authenticated;


-- ─── EVENT MANAGEMENT (§2.2) ─────────────────────────────────
-- "The administrator is the only user type who can create, edit, and publish
-- official Richfield institutional events." 0001 gave events an
-- events_all_admin policy but no guard, so the rule lived entirely in a
-- policy that a future edit could widen by accident. Make it explicit.

CREATE OR REPLACE FUNCTION events_before_write()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only administrators can manage institutional events';
  END IF;
  -- The creator is recorded rather than trusted from the client.
  IF TG_OP = 'INSERT' THEN
    NEW.admin_id := auth.uid();
  ELSE
    NEW.admin_id := OLD.admin_id;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_events_guard ON events;
CREATE TRIGGER trg_events_guard
  BEFORE INSERT OR UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION events_before_write();
