-- ============================================================
-- RTC Hub — 0007: faculty segregation
--
-- Richfield has two faculties, IT and Business, and they are separate
-- audiences. An IT student's post should reach IT students, IT alumni and
-- the companies recruiting IT — and not land in a Business student's feed.
-- The same applies in reverse, and to bounties and opportunities.
--
-- Two facts make this awkward, and they drive the design here:
--
--   * `posts` has no faculty column. The author's faculty lives on
--     `profiles`, and PostgREST cannot filter a parent table by a joined
--     column, so scoping the feed would mean fetching everything and
--     filtering in Dart — which leaks other faculties' content to the
--     device even if the UI hides it. The brief is explicit that hiding on
--     the front end is not enforcement, so faculty is denormalised onto
--     `posts` and set by trigger.
--
--   * A business does not have a faculty. It has an *interest*: a company
--     may recruit IT graduates, Business graduates, or both. That is a
--     separate concept and gets its own column rather than being forced
--     into `faculty`.
--
-- Run after 0006_fix_client_access.sql.
-- ============================================================


-- ─── AUDIENCE ────────────────────────────────────────────────
-- What a given account should see. Students and alumni get their own
-- faculty. Businesses get whatever they opted into at signup. Admins see
-- everything, which is why this can return both.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS content_interests faculty_type[];

COMMENT ON COLUMN profiles.content_interests IS
  'Which faculties this account wants content from. Meaningful for BUSINESS; '
  'for STUDENT/ALUMNI it is kept in step with faculty by trg_profiles_interests.';

-- Students and alumni are not asked this question — their faculty answers it.
-- Keeping the column filled for them too means every audience check is one
-- uniform array lookup instead of a CASE on role.
CREATE OR REPLACE FUNCTION profiles_sync_interests()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NEW.role IN ('STUDENT', 'ALUMNI') THEN
    NEW.content_interests :=
      CASE WHEN NEW.faculty IS NULL THEN NULL ELSE ARRAY[NEW.faculty] END;

  ELSIF NEW.role = 'BUSINESS' THEN
    -- A business that picked nothing sees both rather than an empty app.
    IF NEW.content_interests IS NULL OR CARDINALITY(NEW.content_interests) = 0 THEN
      NEW.content_interests := ARRAY['IT', 'BUSINESS']::faculty_type[];
    END IF;

  ELSE -- ADMIN
    NEW.content_interests := ARRAY['IT', 'BUSINESS']::faculty_type[];
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_profiles_interests ON profiles;
CREATE TRIGGER trg_profiles_interests
  BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION profiles_sync_interests();

-- Backfill accounts that already exist.
UPDATE profiles SET updated_at = NOW();

-- The caller's audience, as an array. SECURITY DEFINER for the same reason
-- my_role() is in 0006: it is read from inside policies on profiles.
CREATE OR REPLACE FUNCTION my_interests()
RETURNS faculty_type[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT COALESCE(
    (SELECT content_interests FROM profiles WHERE id = auth.uid()),
    ARRAY['IT', 'BUSINESS']::faculty_type[]
  );
$fn$;

GRANT EXECUTE ON FUNCTION my_interests() TO authenticated;


-- ─── FACULTY ON POSTS ────────────────────────────────────────
-- Denormalised from the author so the feed can filter server-side. Clients
-- never set it: the trigger overwrites whatever arrives, the same way
-- trg_posts_guard already handles bounty_points.

ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS faculty faculty_type;

COMMENT ON COLUMN posts.faculty IS
  'Copied from the author profile by trg_posts_faculty. Never client-settable. '
  'NULL means the post is visible to both faculties (business-authored posts).';

CREATE OR REPLACE FUNCTION posts_set_faculty()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  author_role user_role;
  author_fac  faculty_type;
BEGIN
  SELECT role, faculty INTO author_role, author_fac
  FROM profiles WHERE id = NEW.author_id;

  IF author_role = 'BUSINESS' THEN
    -- A company posting to students has no faculty of its own. If it
    -- recruits from exactly one faculty the post belongs there; if it
    -- recruits from both, the post is cross-faculty (NULL).
    SELECT CASE
             WHEN CARDINALITY(content_interests) = 1 THEN content_interests[1]
             ELSE NULL
           END
      INTO NEW.faculty
      FROM profiles WHERE id = NEW.author_id;
  ELSE
    NEW.faculty := author_fac;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_posts_faculty ON posts;
CREATE TRIGGER trg_posts_faculty
  BEFORE INSERT OR UPDATE ON posts
  FOR EACH ROW EXECUTE FUNCTION posts_set_faculty();

-- Backfill. Admin-authored posts stay NULL, i.e. visible to everyone.
UPDATE posts p
   SET faculty = pr.faculty
  FROM profiles pr
 WHERE pr.id = p.author_id
   AND pr.role IN ('STUDENT', 'ALUMNI')
   AND p.faculty IS DISTINCT FROM pr.faculty;

CREATE INDEX IF NOT EXISTS idx_posts_faculty ON posts(faculty, created_at DESC);


-- ─── RLS: FACULTY IS ENFORCED, NOT JUST FILTERED ─────────────
-- The guidelines are explicit that hiding screens on the front end is not
-- access control. A Business student querying posts directly must not get
-- IT rows back, so the scoping lives in the policy, not in the Dart.
--
-- NULL faculty is deliberately readable by everyone: that is how
-- cross-faculty announcements and business posts aimed at both cohorts
-- reach their audience.

DROP POLICY IF EXISTS "posts_select" ON posts;
CREATE POLICY "posts_select" ON posts FOR SELECT USING (
  (is_flagged = FALSE OR author_id = auth.uid() OR is_admin())
  AND (
    faculty IS NULL
    OR author_id = auth.uid()
    OR is_admin()
    OR faculty = ANY (my_interests())
  )
);

-- Opportunities already carry required_faculty. Scope them the same way so a
-- Business student is not shown IT-only internships.
DROP POLICY IF EXISTS "opps_select" ON opportunities;
CREATE POLICY "opps_select" ON opportunities FOR SELECT USING (
  (status = 'ACTIVE' OR business_id = auth.uid() OR is_admin())
  AND (
    required_faculty IS NULL
    OR business_id = auth.uid()
    OR is_admin()
    OR required_faculty = ANY (my_interests())
  )
);

-- Events can target a faculty too.
ALTER TABLE events
  ADD COLUMN IF NOT EXISTS faculty faculty_type;

DROP POLICY IF EXISTS "events_select" ON events;
CREATE POLICY "events_select" ON events FOR SELECT USING (
  (faculty IS NULL OR faculty = ANY (my_interests()) OR is_admin())
  -- 0001 ignored target_roles entirely; honour it now.
  AND (target_roles IS NULL OR my_role() = ANY (target_roles) OR is_admin())
);


-- ─── FEED ────────────────────────────────────────────────────
-- PostRepository.feed() used to resolve the caller's connections in Dart and
-- then issue a second query with an `in` filter, which breaks down once the
-- graph is any size. Both steps move into one function here, and faculty
-- scoping comes along for free.

CREATE OR REPLACE FUNCTION feed_post_ids(p_limit INT DEFAULT 20, p_offset INT DEFAULT 0)
RETURNS TABLE (post_id UUID)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $fn$
  WITH circle AS (
    SELECT CASE WHEN c.sender_id = auth.uid() THEN c.receiver_id ELSE c.sender_id END AS uid
      FROM connections c
     WHERE c.status = 'ACCEPTED'
       AND (c.sender_id = auth.uid() OR c.receiver_id = auth.uid())
    UNION
    SELECT auth.uid()
  )
  SELECT p.id
    FROM posts p
   WHERE p.author_id IN (SELECT uid FROM circle)
     AND p.is_flagged = FALSE
   ORDER BY p.created_at DESC
   LIMIT p_limit OFFSET p_offset;
$fn$;

-- SECURITY INVOKER above is deliberate: the posts_select policy still
-- applies inside the function, so faculty scoping cannot be bypassed by
-- calling it.

GRANT EXECUTE ON FUNCTION feed_post_ids(INT, INT) TO authenticated;

-- Relevance-ranked discovery (§2.4 asks for a feed ranked by relevance that
-- behaves differently per role). Recency, engagement, same-course affinity
-- and open bounties all contribute.
CREATE OR REPLACE FUNCTION ranked_feed(p_limit INT DEFAULT 30, p_offset INT DEFAULT 0)
RETURNS TABLE (post_id UUID, score NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $fn$
  WITH me AS (
    SELECT id, role, faculty, course, academic_year
      FROM profiles WHERE id = auth.uid()
  ),
  circle AS (
    SELECT CASE WHEN c.sender_id = auth.uid() THEN c.receiver_id ELSE c.sender_id END AS uid
      FROM connections c
     WHERE c.status = 'ACCEPTED'
       AND (c.sender_id = auth.uid() OR c.receiver_id = auth.uid())
  )
  SELECT p.id,
         -- Recency: full marks for the last hour, decaying over a fortnight.
         GREATEST(0, 14 - EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 86400)::NUMERIC * 2
         -- Engagement.
         + (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id)::NUMERIC * 1.5
         + (SELECT COUNT(*) FROM comments    cm WHERE cm.post_id = p.id)::NUMERIC * 2.0
         -- Someone you are connected to.
         + CASE WHEN p.author_id IN (SELECT uid FROM circle) THEN 15 ELSE 0 END
         -- Same course, then same faculty.
         + CASE WHEN au.course  IS NOT NULL
                 AND au.course  = (SELECT course  FROM me) THEN 8 ELSE 0 END
         + CASE WHEN au.faculty IS NOT NULL
                 AND au.faculty = (SELECT faculty FROM me) THEN 5 ELSE 0 END
         -- Unsolved bounties want answers, so surface them.
         + CASE WHEN p.is_bounty AND NOT p.bounty_solved
                THEN 6 + LEAST(p.bounty_points, 100) / 20.0 ELSE 0 END
         -- Businesses care about who is active, students about peers.
         + CASE WHEN (SELECT role FROM me) = 'BUSINESS' AND au.role = 'STUDENT'
                THEN 4 ELSE 0 END
         AS score
    FROM posts p
    JOIN profiles au ON au.id = p.author_id
   WHERE p.is_flagged = FALSE
     AND p.author_id <> auth.uid()
   ORDER BY score DESC, p.created_at DESC
   LIMIT p_limit OFFSET p_offset;
$fn$;

GRANT EXECUTE ON FUNCTION ranked_feed(INT, INT) TO authenticated;


-- ─── OPPORTUNITY MATCHING, FACULTY-AWARE ─────────────────────
-- 0002's matched_opportunities() scored faculty as a +2 bonus, so an IT
-- student could still be shown Business-only listings, just lower down.
-- Faculty is now a filter, and the weighting is rebalanced.

CREATE OR REPLACE FUNCTION matched_opportunities()
RETURNS TABLE (opportunity_id UUID, score INT)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $fn$
  SELECT o.id,
         (
           SELECT COUNT(*)::INT * 3 FROM skills s
           WHERE s.user_id = auth.uid()
             AND o.required_skills IS NOT NULL
             AND LOWER(s.name) = ANY (SELECT LOWER(x) FROM UNNEST(o.required_skills) AS x)
         )
         + CASE WHEN o.required_faculty IS NOT NULL
                 AND o.required_faculty = (SELECT faculty FROM profiles WHERE id = auth.uid())
                THEN 4 ELSE 0 END
         + CASE WHEN o.required_year IS NOT NULL
                 AND o.required_year = (SELECT academic_year FROM profiles WHERE id = auth.uid())
                THEN 2 ELSE 0 END
         + CASE WHEN o.remote THEN 1 ELSE 0 END AS score
  FROM opportunities o
  WHERE o.status = 'ACTIVE'
    AND (o.expires_at IS NULL OR o.expires_at > NOW())
  ORDER BY score DESC, o.created_at DESC;
$fn$;

GRANT EXECUTE ON FUNCTION matched_opportunities() TO authenticated;


-- ─── NOTIFICATION FAN-OUT, FACULTY-AWARE ─────────────────────
-- 0002 notified every ACTIVE student and alumnus when a listing went live,
-- filtered only by required_faculty. Respect content_interests as well, so
-- nobody is told about an opportunity they cannot see.

CREATE OR REPLACE FUNCTION on_opportunity_activated()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NEW.status = 'ACTIVE' AND OLD.status IS DISTINCT FROM 'ACTIVE' THEN
    INSERT INTO notifications (user_id, type, title, body, data)
    SELECT p.id, 'OPPORTUNITY_MATCH', 'New opportunity: ' || NEW.title,
           'A ' || NEW.type || ' matching your profile was just posted.',
           JSONB_BUILD_OBJECT('opportunity_id', NEW.id)
    FROM profiles p
    WHERE p.role IN ('STUDENT', 'ALUMNI')
      AND p.status = 'ACTIVE'
      AND (NEW.required_faculty IS NULL
           OR p.faculty = NEW.required_faculty);
  END IF;
  RETURN NEW;
END;
$fn$;


-- ─── SIGNUP: CARRY content_interests THROUGH ─────────────────
-- handle_new_user() builds the profiles row from auth metadata, so a
-- business's faculty choice has to be unpacked here or trg_profiles_interests
-- will fall back to "both" and the choice is silently lost.
--
-- Only the INSERT column list differs from 0006's version.

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  meta        JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::JSONB);
  want_role   user_role;
  new_status  account_status;
  clean_email TEXT := LOWER(TRIM(NEW.email));
  local_part  TEXT;
  display     TEXT;
  interests   faculty_type[];
BEGIN
  want_role := COALESCE(NULLIF(meta->>'role', ''), 'STUDENT')::user_role;

  IF want_role = 'ADMIN' THEN
    RAISE EXCEPTION 'Admin accounts cannot be self-registered';
  END IF;

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

  -- jsonb array -> faculty_type[]; anything unrecognised is dropped rather
  -- than raising, so a malformed client cannot block signup.
  IF meta ? 'content_interests' THEN
    SELECT ARRAY_AGG(x::faculty_type)
      INTO interests
      FROM JSONB_ARRAY_ELEMENTS_TEXT(meta->'content_interests') AS x
     WHERE x IN ('IT', 'BUSINESS');
  END IF;

  new_status := CASE WHEN want_role = 'STUDENT' THEN 'ACTIVE' ELSE 'PENDING' END;
  display    := COALESCE(NULLIF(TRIM(meta->>'full_name'), ''), SPLIT_PART(clean_email, '@', 1));

  INSERT INTO profiles (
    id, email, full_name, role, status,
    faculty, course, academic_year, graduation_year,
    company_name, industry, student_number, verification_photo_url,
    content_interests
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
    NULLIF(meta->>'verification_photo_url', ''),
    interests
  );

  INSERT INTO onboarding_progress (user_id) VALUES (NEW.id);

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
