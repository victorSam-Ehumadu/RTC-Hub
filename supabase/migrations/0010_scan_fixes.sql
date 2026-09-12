-- ============================================================
-- RTC Hub — 0010: the database half of the audit findings
--
-- Each of these was found by reading the schema against the code rather
-- than by a failing test, because none of them fails loudly: the leaderboard
-- renders, the counts look plausible, the storage policies accept writes.
-- They are wrong in ways you only notice at a scale a demo never reaches, or
-- from an account whose privacy settings nobody tried.
--
-- Run after 0009_notification_coverage.sql.
-- ============================================================


-- ─── LEADERBOARD PRIVACY ─────────────────────────────────────
-- The `leaderboard` view from 0001 runs with its owner's rights and joins
-- profiles directly, so it lists every ACTIVE student and alumnus by name,
-- avatar and course regardless of visibility_peers / visibility_business.
-- Somebody who hid their profile is still on the leaderboard.
--
-- The obvious fix — ALTER VIEW ... SET (security_invoker = ON) — is wrong
-- here and worth spelling out so nobody "fixes" it that way later: the
-- logic_points policy is `user_id = auth.uid()`, so under invoker rights the
-- SUM would only see the caller's own ledger rows and every other total
-- would collapse to zero. The board would look fine and be entirely false.
--
-- So it becomes a SECURITY DEFINER function instead: it can still total the
-- ledger, and it applies the visibility rules itself.

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
     -- Same visibility test profiles_select applies.
     AND (
       p.id = auth.uid()
       OR is_admin()
       OR CASE WHEN my_role() = 'BUSINESS'
               THEN p.visibility_business
               ELSE p.visibility_peers
          END
     )
     -- And the same faculty scoping, so an IT student's board is IT.
     AND (
       p.faculty IS NULL
       OR p.id = auth.uid()
       OR is_admin()
       OR p.faculty = ANY (my_interests())
     )
   GROUP BY p.id, p.full_name, p.avatar_url, p.course, p.faculty
   ORDER BY total_points DESC, p.full_name
   LIMIT p_limit;
$fn$;

GRANT EXECUTE ON FUNCTION leaderboard_rows(INT) TO authenticated;

-- The view stays for anything already referencing it, but clients lose the
-- ability to read it directly — otherwise the fix above is one query away
-- from being bypassed.
REVOKE ALL ON leaderboard FROM authenticated, anon;


-- ─── COUNTS THAT STOP COUNTING ───────────────────────────────
-- AdminRepository._count() and AnalyticsRepository.forStudent() both select
-- rows and take the list length. PostgREST caps a result set at 1000, so
-- past that the admin dashboard quietly under-reports and the profile shows
-- a student with exactly 1000 posts. Count server-side.

CREATE OR REPLACE FUNCTION admin_stats()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Administrators only';
  END IF;

  RETURN JSONB_BUILD_OBJECT(
    'total_users',            (SELECT COUNT(*) FROM profiles),
    'pending_users',          (SELECT COUNT(*) FROM profiles WHERE status = 'PENDING'),
    'total_posts',            (SELECT COUNT(*) FROM posts),
    'bounties',               (SELECT COUNT(*) FROM posts WHERE is_bounty),
    'pending_opportunities',  (SELECT COUNT(*) FROM opportunities WHERE status = 'PENDING'),
    'open_flags',             (SELECT COUNT(*) FROM content_flags WHERE NOT resolved)
  );
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_stats() TO authenticated;

CREATE OR REPLACE FUNCTION student_stats(uid UUID)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT JSONB_BUILD_OBJECT(
    'logic_points', COALESCE((SELECT SUM(amount) FROM logic_points WHERE user_id = uid), 0),
    'posts',        (SELECT COUNT(*) FROM posts    WHERE author_id = uid),
    'skills',       (SELECT COUNT(*) FROM skills   WHERE user_id = uid),
    'connections',  (SELECT COUNT(*) FROM connections
                      WHERE status = 'ACCEPTED'
                        AND (sender_id = uid OR receiver_id = uid)),
    'profile_views', COALESCE(
      (SELECT SUM(profile_views) FROM profile_analytics WHERE user_id = uid), 0)
  );
$fn$;

GRANT EXECUTE ON FUNCTION student_stats(UUID) TO authenticated;


-- ─── SEARCH WITHOUT FILTER INJECTION ─────────────────────────
-- ProfileRepository.search() interpolates the raw term into a PostgREST
-- `.or()` string. A comma or a closing bracket in the query breaks out of
-- the intended clause and into additional filters. RLS still bounds what can
-- come back, so this is not privilege escalation — but it is a crash and an
-- abuse surface, and it is trivially avoided by doing the matching in SQL.

CREATE OR REPLACE FUNCTION search_profiles(
  p_term  TEXT,
  p_role  user_role DEFAULT NULL,
  p_limit INT DEFAULT 30
)
RETURNS SETOF profiles
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $fn$
  -- SECURITY INVOKER: profiles_select still applies, so this cannot return
  -- anyone the caller could not already look up.
  SELECT *
    FROM profiles p
   WHERE p.id <> auth.uid()
     AND (p_role IS NULL OR p.role = p_role)
     AND (
       COALESCE(TRIM(p_term), '') = ''
       OR p.full_name    ILIKE '%' || p_term || '%'
       OR p.course       ILIKE '%' || p_term || '%'
       OR p.company_name ILIKE '%' || p_term || '%'
       OR p.bio          ILIKE '%' || p_term || '%'
     )
   ORDER BY p.profile_completeness DESC, p.full_name
   LIMIT p_limit;
$fn$;

GRANT EXECUTE ON FUNCTION search_profiles(TEXT, user_role, INT) TO authenticated;


-- ─── PROFILE UPDATE: WITH CHECK ──────────────────────────────
-- profiles_update_own has a USING clause and no WITH CHECK, so the row being
-- written was never re-tested. trg_profiles_guard covers role, status and
-- email, but nothing stopped `id` itself being rewritten.

DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE
  USING (id = auth.uid() OR is_admin())
  WITH CHECK (id = auth.uid() OR is_admin());


-- ─── STORAGE POLICIES SCOPED TO OUR BUCKETS ──────────────────
-- 0002's own_folder_update / own_folder_delete test only the first path
-- segment, with no bucket_id predicate — so they apply to every bucket in
-- the project, including any a teammate adds later for something else
-- entirely. Narrow them to the buckets this app owns.

DROP POLICY IF EXISTS "own_folder_update" ON storage.objects;
CREATE POLICY "own_folder_update" ON storage.objects FOR UPDATE
  USING (
    bucket_id IN ('avatars', 'post-media', 'documents', 'verification', 'submissions')
    AND auth.uid()::TEXT = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "own_folder_delete" ON storage.objects;
CREATE POLICY "own_folder_delete" ON storage.objects FOR DELETE
  USING (
    bucket_id IN ('avatars', 'post-media', 'documents', 'verification', 'submissions')
    AND (auth.uid()::TEXT = (storage.foldername(name))[1] OR is_admin())
  );


-- ─── BOUNTY ESCALATION ───────────────────────────────────────
-- escalate_bounties() has existed since 0001 and has never run: there is no
-- schedule anywhere, so "unsolved bounties rise in value over time" is a
-- feature described in the proposal and implemented nowhere.
--
-- It is still not scheduled here, for the same reason prune_notifications()
-- is not in 0009: pg_cron has to be enabled on the project first, and a
-- migration that assumes the extension fails outright on a project that has
-- not enabled it. Enable it under Database → Extensions, then:
--
--   SELECT cron.schedule('escalate-bounties', '0 * * * *',
--                        $$SELECT escalate_bounties()$$);
--   SELECT cron.schedule('prune-notifications', '0 3 * * *',
--                        $$SELECT prune_notifications()$$);
--
-- Until then it can be run by hand from the SQL editor, which is also how to
-- demo it without waiting an hour.
--
-- The rewrite below adds the part that was missing even when it did run:
-- telling the author their bounty went up, and returning a count so a manual
-- run reports what it did.

-- 0001 declared this RETURNS VOID. CREATE OR REPLACE cannot change a return
-- type, so the old one has to go first — Postgres says as much (42P13).
-- Dropping is safe: nothing references it, which is the whole problem.
DROP FUNCTION IF EXISTS escalate_bounties();

CREATE FUNCTION escalate_bounties()
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE moved INT;
BEGIN
  WITH bumped AS (
    UPDATE posts
       SET bounty_points = LEAST(bounty_points + 5, 500)
     WHERE is_bounty
       AND NOT bounty_solved
       AND created_at < NOW() - INTERVAL '24 hours'
       AND bounty_points < 500
    RETURNING id, author_id, bounty_points, content
  )
  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT b.author_id, 'BOUNTY_SOLVED',
         'Your bounty is now worth ' || b.bounty_points || ' LP',
         'Still unsolved, so the reward went up. ' || LEFT(b.content, 60),
         JSONB_BUILD_OBJECT('post_id', b.id, 'points', b.bounty_points)
    FROM bumped b;

  GET DIAGNOSTICS moved = ROW_COUNT;
  RETURN moved;
END;
$fn$;
