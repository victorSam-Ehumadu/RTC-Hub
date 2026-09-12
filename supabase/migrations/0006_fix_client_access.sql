-- ============================================================
-- RTC Hub — 0006: make the client-direct model actually work
--
-- 0001 built the schema and 0002 moved authorization into the database, but
-- the app had never been pointed at a real project, so three faults that only
-- appear at runtime went unnoticed. Every one of them blocks the app at
-- launch; none of them is visible to `flutter analyze` or to demo mode.
--
--   1. No table privileges. 0002 grants EXECUTE on five functions and nothing
--      else, relying on Supabase's default privileges to cover the tables.
--      On this project they did not apply, so PostgREST answers every query
--      with 42501 "permission denied for table" — a GRANT failure, which
--      happens one layer *before* RLS is consulted.
--
--   2. Infinite recursion in the profiles policy. `is_admin()` reads
--      `profiles`, and `profiles_select` calls `is_admin()` — and separately
--      inlines `(SELECT role FROM profiles ...)`. Postgres applies RLS to
--      those subqueries too, so the policy invokes itself: 42P17. Because
--      ~30 policies on other tables call `is_admin()`, and most app queries
--      embed `author:profiles!author_id(...)`, this takes down every screen,
--      not just the profile.
--
--   3. Student email domains. The brief requires @aaa.ac.za alongside
--      @richfield.ac.za; handle_new_user() rejects the former outright.
--
-- Numbered 0006 so streams A/B/C keep 0003/0004/0005 (see WORKPLAN.md).
-- Run after 0002_client_direct_access.sql.
-- ============================================================


-- ─── 1. TABLE PRIVILEGES ─────────────────────────────────────
-- GRANT and RLS are two different gates. GRANT decides whether a role may
-- touch a table at all; RLS then decides which rows come back. Granting DML
-- broadly here is safe *because* 0001 enabled RLS on every one of these
-- tables and 0002 wrote the policies — a grant without a matching policy
-- still returns nothing.
--
-- Only `authenticated` is granted. `anon` deliberately gets nothing: every
-- screen in the app sits behind the router's auth redirect, and several
-- policies use `USING (TRUE)` (skills, work_experience, events, reactions,
-- endorsements, archives), which would otherwise be world-readable to anyone
-- holding the publishable key.

GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON ALL TABLES IN SCHEMA public
  TO authenticated;

-- The two ledger tables are read-only to clients. RLS already denies writes
-- (neither has an INSERT/UPDATE/DELETE policy), so this is defence in depth:
-- if someone later adds a policy without thinking, the missing grant still
-- stops it. logic_points is written only by accept_bounty_solution(),
-- profile_analytics only by record_profile_view().
REVOKE INSERT, UPDATE, DELETE ON logic_points      FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON profile_analytics FROM authenticated;

-- Tables added by later migrations should inherit the same treatment rather
-- than silently landing unreachable, which is the bug this section fixes.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;


-- ─── 2. RECURSION IN THE PROFILES POLICY ─────────────────────
-- Both helpers below read `profiles` from inside `profiles`' own SELECT
-- policy. SECURITY DEFINER makes them run as the owner, which bypasses RLS
-- for that lookup and breaks the cycle. They are STABLE so the planner
-- evaluates them once per statement rather than once per row.
--
-- These are safe to expose: they answer only "what is the caller's role",
-- never "what is anyone else's", and take no argument that could be pointed
-- at another user.

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'
  );
$fn$;

-- Replaces the inline `(SELECT role FROM profiles me WHERE me.id = auth.uid())`
-- that 0002 embedded directly in the policy below.
CREATE OR REPLACE FUNCTION my_role()
RETURNS user_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT role FROM profiles WHERE id = auth.uid();
$fn$;

DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid()
  OR is_admin()
  OR (
    status = 'ACTIVE'
    AND CASE
          WHEN my_role() = 'BUSINESS' THEN visibility_business
          ELSE visibility_peers
        END
  )
);

GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION my_role()  TO authenticated;


-- ─── 3. STUDENT EMAIL DOMAINS ────────────────────────────────
-- §2.1 requires @my.aaa.ac.za and @aaa.ac.za alongside the Richfield
-- domains. The rule is mirrored in lib/core/constants.dart so the user gets
-- a message before the network round-trip; both sides must agree.
--
-- Everything else in this function is unchanged from 0002.

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  meta        JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::JSONB);
  want_role   user_role;
  new_status  account_status;
  clean_email TEXT := LOWER(TRIM(NEW.email));
  local_part  TEXT;
  display     TEXT;
BEGIN
  want_role := COALESCE(NULLIF(meta->>'role', ''), 'STUDENT')::user_role;

  -- Nobody self-registers as an admin.
  IF want_role = 'ADMIN' THEN
    RAISE EXCEPTION 'Admin accounts cannot be self-registered';
  END IF;

  -- Campus domain + 9-digit student number enforcement.
  IF want_role = 'STUDENT' THEN
    IF clean_email NOT LIKE '%@my.richfield.ac.za'
       AND clean_email NOT LIKE '%@richfield.ac.za'
       AND clean_email NOT LIKE '%@my.aaa.ac.za'
       AND clean_email NOT LIKE '%@aaa.ac.za' THEN
      RAISE EXCEPTION 'Student registration requires a Richfield or AAA email address';
    END IF;
    local_part := SPLIT_PART(clean_email, '@', 1);
    IF local_part !~ '^[0-9]{9}$' THEN
      RAISE EXCEPTION 'Student email prefix must be exactly 9 digits';
    END IF;
  END IF;

  -- Students are trusted by their domain; everyone else waits for an admin.
  new_status := CASE WHEN want_role = 'STUDENT' THEN 'ACTIVE' ELSE 'PENDING' END;
  display    := COALESCE(NULLIF(TRIM(meta->>'full_name'), ''), SPLIT_PART(clean_email, '@', 1));

  INSERT INTO profiles (
    id, email, full_name, role, status,
    faculty, course, academic_year, graduation_year,
    company_name, industry, student_number, verification_photo_url
  ) VALUES (
    NEW.id,
    clean_email,
    display,
    want_role,
    new_status,
    NULLIF(meta->>'faculty', '')::faculty_type,
    NULLIF(meta->>'course', ''),
    NULLIF(meta->>'academic_year', ''),
    NULLIF(meta->>'graduation_year', '')::INT,
    NULLIF(meta->>'company_name', ''),
    NULLIF(meta->>'industry', ''),
    CASE WHEN want_role = 'STUDENT' THEN SPLIT_PART(clean_email, '@', 1)
         ELSE NULLIF(meta->>'student_number', '') END,
    NULLIF(meta->>'verification_photo_url', '')
  );

  INSERT INTO onboarding_progress (user_id) VALUES (NEW.id);

  -- Queue the account for admin review. Typed ADMIN_ANNOUNCEMENT rather than
  -- ACCOUNT_APPROVED (which 0002 used) so the notifications list does not
  -- render "needs review" with a green approved icon.
  IF new_status = 'PENDING' THEN
    INSERT INTO notifications (user_id, type, title, body, data)
    SELECT p.id, 'ADMIN_ANNOUNCEMENT',
           'New account pending approval',
           display || ' registered as ' || want_role || ' and needs review.',
           JSONB_BUILD_OBJECT('pending_user_id', NEW.id)
    FROM profiles p WHERE p.role = 'ADMIN';
  END IF;

  RETURN NEW;
END;
$fn$;


-- ─── 4. FOREIGN KEYS THAT BLOCK DELETES ──────────────────────
-- 0001 declared these without an ON DELETE action, so the default NO ACTION
-- applies and the parent row cannot be removed. In practice:
--
--   * deleting a post that ever paid out a bounty fails (logic_points.post_id)
--   * deleting a post or comment that was ever reported fails (content_flags)
--   * deleting an account that ever filed a report fails (reporter_id)
--   * deleting a comment that has replies fails (comments.parent_id)
--
-- All four are reachable from the UI, so end-to-end testing hits them.
-- The ledger keeps its row when a post goes (SET NULL) because the points
-- were genuinely earned; flags and replies go with their parent.

ALTER TABLE logic_points
  DROP CONSTRAINT IF EXISTS logic_points_post_id_fkey,
  ADD  CONSTRAINT logic_points_post_id_fkey
       FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE SET NULL;

ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_post_id_fkey,
  ADD  CONSTRAINT content_flags_post_id_fkey
       FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;

ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_comment_id_fkey,
  ADD  CONSTRAINT content_flags_comment_id_fkey
       FOREIGN KEY (comment_id) REFERENCES comments(id) ON DELETE CASCADE;

ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_reporter_id_fkey,
  ADD  CONSTRAINT content_flags_reporter_id_fkey
       FOREIGN KEY (reporter_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_user_id_fkey,
  ADD  CONSTRAINT content_flags_user_id_fkey
       FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_resolved_by_fkey,
  ADD  CONSTRAINT content_flags_resolved_by_fkey
       FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE comments
  DROP CONSTRAINT IF EXISTS comments_parent_id_fkey,
  ADD  CONSTRAINT comments_parent_id_fkey
       FOREIGN KEY (parent_id) REFERENCES comments(id) ON DELETE CASCADE;


-- ─── VERIFY ──────────────────────────────────────────────────
-- Run this on its own after the migration. It should return one row reading
-- t | t | t. If `recursion_fixed` is false the policy still self-references;
-- if `profiles_readable` errors with 42P17 the helpers did not take.

-- SELECT
--   has_table_privilege('authenticated', 'profiles', 'SELECT') AS grants_ok,
--   (SELECT prosecdef FROM pg_proc WHERE proname = 'is_admin')  AS recursion_fixed,
--   EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'my_role')    AS helper_present;
