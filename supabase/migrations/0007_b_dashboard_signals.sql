-- ============================================================
-- RTC Hub — 0007 (Stream B): programme completeness + skill signals
--
-- Closes the last two §2.7 student-dashboard metrics: "completeness vs.
-- programme peers" and "most-searched skills". By product decision the
-- second one is actually two separate dashboard sections, since the app
-- has no real search log to draw a single number from:
--   - skills businesses want   — aggregated from opportunities.required_skills
--   - skills people search for — a new counter fed by the existing
--     people-search box (ProfileRepository.search), incremented only when
--     the typed term matches a real entry in the skills catalog
--
-- Run after 0006_b_student_dashboard.sql.
-- ============================================================

-- ─── COMPLETENESS VS. PROGRAMME PEERS ────────────────────────
-- Deliberately plain SQL, not SECURITY DEFINER: this runs as the caller, so
-- profiles_select's visibility_peers/ACTIVE checks apply exactly as they
-- would to a manual query — a classmate who has hidden themselves from
-- peers is silently excluded from the average, same as everywhere else.
CREATE OR REPLACE FUNCTION programme_completeness(p_course TEXT)
RETURNS TABLE(avg_completeness NUMERIC, peer_count BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(AVG(profile_completeness), 0)::NUMERIC, COUNT(*)
  FROM profiles
  WHERE course = p_course AND role = 'STUDENT' AND id <> auth.uid();
$$;

GRANT EXECUTE ON FUNCTION programme_completeness(TEXT) TO authenticated;

-- ─── SKILLS BUSINESSES WANT ──────────────────────────────────
-- unnest() over required_skills, also plain SQL so opps_select applies as
-- invoker — a student only ever aggregates ACTIVE listings here, the same
-- set they could browse directly. idx_opportunities_skills (0001) covers
-- the unnest.
CREATE OR REPLACE FUNCTION top_wanted_skills(p_limit INT DEFAULT 8)
RETURNS TABLE(skill TEXT, listings BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT s, COUNT(*)
  FROM opportunities, unnest(required_skills) AS s
  GROUP BY s
  ORDER BY COUNT(*) DESC, s
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION top_wanted_skills(INT) TO authenticated;

-- ─── SKILLS PEOPLE SEARCH FOR ────────────────────────────────
-- A global, unattributed counter — no user_id column, so nothing here
-- identifies who searched what, and unlike profile_analytics it needs no
-- owner-only SELECT policy: anyone signed in can read it, same as the
-- skills catalog it draws from.
CREATE TABLE skill_search_counts (
  skill_name    TEXT PRIMARY KEY,
  search_count  INT NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE skill_search_counts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "skill_search_select_all" ON skill_search_counts
  FOR SELECT USING (TRUE);
-- No INSERT/UPDATE policy: writable only through log_skill_search() below,
-- same shape as profile_analytics being written only through
-- record_profile_view().

-- Counts a search only when the typed term matches a real skill in the
-- catalog (case-insensitive) — free text that doesn't resolve to a known
-- skill is silently ignored, so this stays "most-searched skills" rather
-- than "most-typed text". Called from ProfileRepository.search() alongside
-- every people-search, fire-and-forget like record_profile_view().
CREATE OR REPLACE FUNCTION log_skill_search(p_term TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE matched TEXT;
BEGIN
  SELECT name INTO matched FROM skills WHERE lower(name) = lower(trim(p_term)) LIMIT 1;
  IF matched IS NULL THEN RETURN; END IF;

  INSERT INTO skill_search_counts (skill_name, search_count, updated_at)
  VALUES (matched, 1, NOW())
  ON CONFLICT (skill_name) DO UPDATE
    SET search_count = skill_search_counts.search_count + 1, updated_at = NOW();
END;
$fn$;

GRANT EXECUTE ON FUNCTION log_skill_search(TEXT) TO authenticated;
