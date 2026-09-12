-- ============================================================
-- RTC Hub — 0011: §2.3 profile requirements, plus saved items
--
-- Three mandatory clauses in §2.3 had no implementation at all:
--
--   * written recommendations and testimonials
--   * per-section profile visibility controls
--   * a business company profile — website, contact details, talent sought
--
-- Per-section visibility is the interesting one, because the obvious
-- implementation is not enforcement. RLS is row-level: it can decide whether
-- you may read a profile row, but not whether you may read the `cv_url`
-- column of that row. Hiding a section in Dart leaves the data in the JSON
-- the device already received, which the guidelines call out explicitly as
-- insufficient. So there is a reader function below that strips hidden
-- sections server-side, and the app uses it for anyone else's profile.
--
-- Run after 0010_scan_fixes.sql.
-- ============================================================


-- ─── COMPANY PROFILE (§2.3) ──────────────────────────────────
-- `talent_description` already existed. The rest of what the brief asks a
-- business to publish did not.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS website_url    TEXT,
  ADD COLUMN IF NOT EXISTS contact_email  TEXT,
  ADD COLUMN IF NOT EXISTS contact_phone  TEXT,
  ADD COLUMN IF NOT EXISTS company_size   TEXT,
  ADD COLUMN IF NOT EXISTS founded_year   INT,
  ADD COLUMN IF NOT EXISTS headline       TEXT;

COMMENT ON COLUMN profiles.headline IS
  'One line under the name — "3rd year BSc IT, looking for an internship". '
  'Applies to every role, not just businesses.';


-- ─── PER-SECTION VISIBILITY (§2.3) ───────────────────────────
-- A single JSONB map rather than a column per section: the set of sections
-- will move as the app grows, and a migration per toggle is not worth it.
-- Unknown keys read as visible, so adding a section later does not silently
-- hide it for everyone who saved settings before it existed.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS section_visibility JSONB NOT NULL DEFAULT '{}'::JSONB;

COMMENT ON COLUMN profiles.section_visibility IS
  'Per-section overrides, e.g. {"cv": false, "contact": false}. Absent key '
  'means visible. Enforced by profile_for_viewer(), not by the client.';

-- Is one section of `target`'s profile readable by the caller?
CREATE OR REPLACE FUNCTION section_visible(target UUID, section TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT CASE
    -- Your own profile, and an admin's view of it, are never filtered.
    WHEN target = auth.uid() OR is_admin() THEN TRUE
    ELSE COALESCE((SELECT (section_visibility->>section)::BOOLEAN
                     FROM profiles WHERE id = target), TRUE)
  END;
$fn$;

GRANT EXECUTE ON FUNCTION section_visible(UUID, TEXT) TO authenticated;

-- The profile as this viewer is allowed to see it.
--
-- Returns JSONB rather than SETOF profiles because the whole point is that
-- some columns are absent — a typed row would have to null them, and "null"
-- and "hidden" are different things the UI should not have to guess between.
CREATE OR REPLACE FUNCTION profile_for_viewer(target UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  row_data JSONB;
  is_self  BOOLEAN := (target = auth.uid());
  vis      JSONB;
BEGIN
  -- Row-level visibility still decides whether there is anything to return
  -- at all; this function narrows, it never widens.
  IF NOT EXISTS (
    SELECT 1 FROM profiles p
     WHERE p.id = target
       AND (
         p.id = auth.uid()
         OR is_admin()
         OR (p.status = 'ACTIVE' AND CASE WHEN my_role() = 'BUSINESS'
                                          THEN p.visibility_business
                                          ELSE p.visibility_peers END)
       )
  ) THEN
    RETURN NULL;
  END IF;

  SELECT TO_JSONB(p), COALESCE(p.section_visibility, '{}'::JSONB)
    INTO row_data, vis
    FROM profiles p WHERE p.id = target;

  IF is_self OR is_admin() THEN
    RETURN row_data;
  END IF;

  -- Strip the sections this viewer may not see. Absent key = visible.
  IF (vis->>'contact') = 'false' THEN
    row_data := row_data - 'contact_email' - 'contact_phone' - 'email';
  END IF;
  IF (vis->>'cv') = 'false' THEN
    row_data := row_data - 'cv_url';
  END IF;
  IF (vis->>'portfolio') = 'false' THEN
    row_data := row_data - 'portfolio_url';
  END IF;
  IF (vis->>'bio') = 'false' THEN
    row_data := row_data - 'bio' - 'headline';
  END IF;
  IF (vis->>'studies') = 'false' THEN
    row_data := row_data - 'course' - 'academic_year' - 'graduation_year';
  END IF;

  -- Never leaks regardless of settings: nothing outside the account needs
  -- the student number, and it is the one field that identifies a person to
  -- the institution.
  RETURN row_data - 'student_number' - 'verification_photo_url';
END;
$fn$;

GRANT EXECUTE ON FUNCTION profile_for_viewer(UUID) TO authenticated;


-- ─── RECOMMENDATIONS AND TESTIMONIALS (§2.3) ─────────────────
-- Written by one person about another. Not visible until the subject
-- approves, for the obvious reason: a profile is a professional record, and
-- anyone being able to staple text to someone else's is a harassment vector
-- rather than a feature.

CREATE TABLE IF NOT EXISTS recommendations (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  subject_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  body         TEXT NOT NULL,
  relationship TEXT,            -- "Lectured me", "Worked together at ..."
  approved     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  CHECK (author_id <> subject_id),
  UNIQUE (author_id, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_recommendations_subject
  ON recommendations(subject_id, approved);

ALTER TABLE recommendations ENABLE ROW LEVEL SECURITY;

-- Approved ones are public; a pending one is visible to the two people
-- involved so each can see it exists.
DROP POLICY IF EXISTS "recommendations_select" ON recommendations;
CREATE POLICY "recommendations_select" ON recommendations FOR SELECT USING (
  approved
  OR author_id = auth.uid()
  OR subject_id = auth.uid()
  OR is_admin()
);

DROP POLICY IF EXISTS "recommendations_insert" ON recommendations;
CREATE POLICY "recommendations_insert" ON recommendations FOR INSERT
  WITH CHECK (author_id = auth.uid());

-- The subject approves or hides; the author edits their own words. Both
-- need UPDATE, and the trigger below decides which columns each may move.
DROP POLICY IF EXISTS "recommendations_update" ON recommendations;
CREATE POLICY "recommendations_update" ON recommendations FOR UPDATE
  USING (author_id = auth.uid() OR subject_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "recommendations_delete" ON recommendations;
CREATE POLICY "recommendations_delete" ON recommendations FOR DELETE
  USING (author_id = auth.uid() OR subject_id = auth.uid() OR is_admin());

-- An author must not be able to approve their own recommendation, and a
-- subject must not be able to edit the words attributed to someone else.
CREATE OR REPLACE FUNCTION recommendations_before_write()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.approved := FALSE;
    RETURN NEW;
  END IF;

  IF is_admin() THEN RETURN NEW; END IF;

  IF auth.uid() = OLD.author_id THEN
    -- The author owns the text, never the approval.
    NEW.approved   := OLD.approved;
    NEW.subject_id := OLD.subject_id;
  ELSIF auth.uid() = OLD.subject_id THEN
    -- The subject owns the approval, never the text.
    NEW.body         := OLD.body;
    NEW.relationship := OLD.relationship;
    NEW.author_id    := OLD.author_id;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_recommendations_guard ON recommendations;
CREATE TRIGGER trg_recommendations_guard
  BEFORE INSERT OR UPDATE ON recommendations
  FOR EACH ROW EXECUTE FUNCTION recommendations_before_write();

CREATE OR REPLACE FUNCTION on_recommendation_written()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE actor TEXT;
BEGIN
  SELECT full_name INTO actor FROM profiles WHERE id = NEW.author_id;

  IF TG_OP = 'INSERT' THEN
    PERFORM notify(NEW.subject_id, 'SKILL_ENDORSED',
                   'You have a new recommendation',
                   actor || ' wrote one. Approve it to show it on your profile.',
                   JSONB_BUILD_OBJECT('recommendation_id', NEW.id,
                                      'author_id', NEW.author_id));
  ELSIF NEW.approved AND NOT OLD.approved THEN
    PERFORM notify(NEW.author_id, 'SKILL_ENDORSED',
                   'Your recommendation is live',
                   'It now appears on their profile.',
                   JSONB_BUILD_OBJECT('recommendation_id', NEW.id,
                                      'user_id', NEW.subject_id));
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_recommendation_notify ON recommendations;
CREATE TRIGGER trg_recommendation_notify
  AFTER INSERT OR UPDATE ON recommendations
  FOR EACH ROW EXECUTE FUNCTION on_recommendation_written();


-- ─── SAVED POSTS AND OPPORTUNITIES ───────────────────────────
-- A student sees a listing between lectures and wants it at the weekend.
-- One table with a nullable pair rather than two, so "my saved items" is a
-- single query and the UI can show one list.

CREATE TABLE IF NOT EXISTS saved_items (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id        UUID REFERENCES posts(id) ON DELETE CASCADE,
  opportunity_id UUID REFERENCES opportunities(id) ON DELETE CASCADE,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  -- Exactly one target.
  CHECK (num_nonnulls(post_id, opportunity_id) = 1),
  UNIQUE (user_id, post_id),
  UNIQUE (user_id, opportunity_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_items_user
  ON saved_items(user_id, created_at DESC);

ALTER TABLE saved_items ENABLE ROW LEVEL SECURITY;

-- Entirely private. Nobody needs to know what someone else bookmarked, and
-- there is no feature that wants it.
DROP POLICY IF EXISTS "saved_items_own" ON saved_items;
CREATE POLICY "saved_items_own" ON saved_items FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON recommendations, saved_items TO authenticated;


-- ─── UNIFIED SEARCH ──────────────────────────────────────────
-- People, posts and opportunities in one call. Doing it as three round
-- trips from the device meant three spinners and no way to rank across
-- them; doing it here also means faculty scoping applies for free, because
-- each SELECT still runs under the caller's policies.

CREATE OR REPLACE FUNCTION search_everything(p_term TEXT, p_limit INT DEFAULT 10)
RETURNS TABLE (
  kind     TEXT,
  id       UUID,
  title    TEXT,
  subtitle TEXT,
  extra    JSONB
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $fn$
  WITH term AS (SELECT '%' || COALESCE(TRIM(p_term), '') || '%' AS q)
  (
    SELECT 'profile', p.id, p.full_name,
           COALESCE(p.headline, p.course, p.company_name, p.role::TEXT),
           JSONB_BUILD_OBJECT('avatar_url', p.avatar_url, 'role', p.role)
      FROM profiles p, term
     WHERE p.id <> auth.uid()
       AND (p.full_name ILIKE term.q OR p.course ILIKE term.q
            OR p.company_name ILIKE term.q OR p.headline ILIKE term.q)
     LIMIT p_limit
  )
  UNION ALL
  (
    SELECT 'post', po.id, LEFT(po.content, 80),
           COALESCE(au.full_name, 'Unknown'),
           JSONB_BUILD_OBJECT('is_bounty', po.is_bounty,
                              'bounty_points', po.bounty_points,
                              'faculty', po.faculty)
      FROM posts po JOIN profiles au ON au.id = po.author_id, term
     WHERE po.is_flagged = FALSE
       AND (po.content ILIKE term.q OR po.code_snippet ILIKE term.q
            OR po.bounty_module ILIKE term.q)
     ORDER BY po.created_at DESC
     LIMIT p_limit
  )
  UNION ALL
  (
    SELECT 'opportunity', o.id, o.title,
           COALESCE(b.company_name, b.full_name),
           JSONB_BUILD_OBJECT('type', o.type, 'remote', o.remote,
                              'required_faculty', o.required_faculty)
      FROM opportunities o JOIN profiles b ON b.id = o.business_id, term
     WHERE o.status = 'ACTIVE'
       AND (o.title ILIKE term.q OR o.description ILIKE term.q)
     ORDER BY o.created_at DESC
     LIMIT p_limit
  );
$fn$;

GRANT EXECUTE ON FUNCTION search_everything(TEXT, INT) TO authenticated;


-- ─── CONNECTION SUGGESTIONS ──────────────────────────────────
-- "People you may know", scored on what this app actually knows: the same
-- course, the same faculty, shared skills, and mutual connections.

CREATE OR REPLACE FUNCTION suggested_connections(p_limit INT DEFAULT 10)
RETURNS TABLE (id UUID, score INT, reason TEXT)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $fn$
  WITH me AS (SELECT * FROM profiles WHERE id = auth.uid()),
  linked AS (
    SELECT CASE WHEN sender_id = auth.uid() THEN receiver_id ELSE sender_id END AS uid
      FROM connections
     WHERE sender_id = auth.uid() OR receiver_id = auth.uid()
  )
  SELECT p.id,
         (
           CASE WHEN p.course = (SELECT course FROM me) THEN 5 ELSE 0 END
         + CASE WHEN p.faculty = (SELECT faculty FROM me) THEN 3 ELSE 0 END
         + (SELECT COUNT(*)::INT FROM skills s1
             WHERE s1.user_id = p.id
               AND LOWER(s1.name) IN (SELECT LOWER(name) FROM skills
                                       WHERE user_id = auth.uid()))
         + (SELECT COUNT(*)::INT FROM linked l
             WHERE l.uid IN (
               SELECT CASE WHEN c2.sender_id = p.id THEN c2.receiver_id
                           ELSE c2.sender_id END
                 FROM connections c2
                WHERE c2.status = 'ACCEPTED'
                  AND (c2.sender_id = p.id OR c2.receiver_id = p.id)))
         )::INT AS score,
         CASE
           WHEN p.course = (SELECT course FROM me) THEN 'Same course'
           WHEN p.faculty = (SELECT faculty FROM me) THEN 'Same faculty'
           ELSE 'Suggested for you'
         END AS reason
    FROM profiles p
   WHERE p.id <> auth.uid()
     AND p.status = 'ACTIVE'
     AND p.id NOT IN (SELECT uid FROM linked)
   ORDER BY score DESC, p.profile_completeness DESC
   LIMIT p_limit;
$fn$;

GRANT EXECUTE ON FUNCTION suggested_connections(INT) TO authenticated;
