-- ============================================================
-- RTC Hub — 0008 (Stream B): scope "most-searched skills" correctly
--
-- 0007 built a platform-wide top-8 skill-search leaderboard. Re-reading
-- §2.7 directly (not WORKPLAN's paraphrase) instead of code, the actual
-- requirement is narrower: "which of THEIR skills are most searched for
-- BY BUSINESS USERS". Two scoping mistakes to fix:
--   1. It's the viewing student's own skills, not a global list.
--   2. It only counts searches performed by BUSINESS-role users, not
--      anyone's search.
--
-- log_skill_search() itself needs no new signature — the fix lives inside
-- it, using my_role() (0003) exactly like every other role check in this
-- codebase. Run after 0007_b_dashboard_signals.sql.
-- ============================================================

CREATE OR REPLACE FUNCTION log_skill_search(p_term TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE matched TEXT;
BEGIN
  IF my_role() <> 'BUSINESS' THEN RETURN; END IF;

  SELECT name INTO matched FROM skills WHERE lower(name) = lower(trim(p_term)) LIMIT 1;
  IF matched IS NULL THEN RETURN; END IF;

  INSERT INTO skill_search_counts (skill_name, search_count, updated_at)
  VALUES (matched, 1, NOW())
  ON CONFLICT (skill_name) DO UPDATE
    SET search_count = skill_search_counts.search_count + 1, updated_at = NOW();
END;
$fn$;

-- Caller's own skills, cross-referenced against the (now business-only)
-- search counts. skills(user_id, name) is UNIQUE (0001), so no de-dup
-- needed on the join.
CREATE OR REPLACE FUNCTION my_searched_skills(p_limit INT DEFAULT 8)
RETURNS TABLE(skill_name TEXT, search_count INT)
LANGUAGE sql STABLE AS $$
  SELECT c.skill_name, c.search_count
  FROM skill_search_counts c
  JOIN skills s ON lower(s.name) = lower(c.skill_name)
  WHERE s.user_id = auth.uid()
  ORDER BY c.search_count DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION my_searched_skills(INT) TO authenticated;
