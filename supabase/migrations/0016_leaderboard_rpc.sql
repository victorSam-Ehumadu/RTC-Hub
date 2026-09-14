-- ============================================================
-- RTC Hub — 0016: leaderboard as a SECURITY DEFINER function, not a view
--
-- `leaderboard` (0001) runs with its owner's rights by design — 0002's own
-- comment says so, reasoning that filtering to ACTIVE students/alumni made
-- it "safe as-is". That filter alone misses the privacy dimension:
-- visibility_peers/visibility_business let a user hide their profile from
-- other students/businesses, and the view ignores both, so a user who
-- opted out still shows up on the leaderboard by name, avatar and course.
--
-- Separately, a plain client SELECT against this view has been reported as
-- returning 42501 ("permission denied") for ordinary users on the live
-- project — not reproducible from the migrations alone (a SELECT blocked
-- by RLS returns zero rows, not 42501; a real 42501 here points to a
-- GRANT/role/session issue on the live database, not a schema defect), but
-- moving this to an explicit GRANT EXECUTE on a function, and revoking
-- direct table/view access, removes the ambiguity either way.
--
-- The obvious "fix" — ALTER VIEW leaderboard SET (security_invoker = ON) —
-- is wrong and worth ruling out explicitly: logic_points' SELECT policy is
-- `user_id = auth.uid()`, so under invoker rights SUM(lp.amount) would only
-- ever see the caller's own ledger rows, and every other total would
-- silently collapse to zero. The board would render, look plausible, and be
-- entirely false. A SECURITY DEFINER function keeps the owner-rights
-- aggregate correct while applying the visibility check itself.
--
-- Run after 0001_initial_schema.sql.
-- ============================================================

CREATE OR REPLACE FUNCTION leaderboard_rows(p_limit INT DEFAULT 25)
RETURNS TABLE (
  id           UUID,
  full_name    TEXT,
  avatar_url   TEXT,
  course       TEXT,
  faculty      faculty_type,
  total_points INT,
  skill_count  INT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT p.id,
         p.full_name,
         p.avatar_url,
         p.course,
         p.faculty,
         COALESCE(SUM(lp.amount), 0)::INT AS total_points,
         COUNT(DISTINCT s.id)::INT        AS skill_count
    FROM profiles p
    LEFT JOIN logic_points lp ON lp.user_id = p.id
    LEFT JOIN skills       s  ON s.user_id  = p.id
   WHERE p.role IN ('STUDENT', 'ALUMNI')
     AND p.status = 'ACTIVE'
     -- Same visibility a peer viewing this profile directly would get.
     AND (p.id = auth.uid() OR is_admin() OR p.visibility_peers)
   GROUP BY p.id, p.full_name, p.avatar_url, p.course, p.faculty
   ORDER BY total_points DESC, p.full_name
   LIMIT p_limit;
$fn$;

GRANT EXECUTE ON FUNCTION leaderboard_rows(INT) TO authenticated;

-- The view stays (things may still reference it), but clients lose direct
-- read access — otherwise the visibility check above is one query away
-- from being bypassed.
REVOKE ALL ON leaderboard FROM authenticated, anon;
