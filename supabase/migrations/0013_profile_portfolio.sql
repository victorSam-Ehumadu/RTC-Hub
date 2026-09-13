-- ============================================================
-- RTC Hub — 0013: the rest of the §2.3 profile
--
-- §2.3 is explicit that a profile must serve "as a digital portfolio rather
-- than simply displaying a user's name and photograph", and then lists what
-- that means. Roughly thirteen of those items had nowhere to live.
--
-- Two shapes, chosen per item rather than uniformly:
--
--   * Single values that a search or a dashboard might one day filter on —
--     campus, enrolment year, GitHub handle, Credly link — are columns.
--   * Repeating entries with their own structure — projects, certifications,
--     achievements, leadership roles, activities — are child tables. They
--     are lists a user adds to and removes from one at a time, and a JSONB
--     blob would make "delete the third certification" a read-modify-write
--     of the whole profile.
--
-- Entrepreneurial experience reuses `work_experience` rather than getting a
-- table of its own: a founded startup has a title, an organisation and a
-- date range like any other role. A `kind` column separates the two so the
-- profile can show them under different headings, which is all §2.3 asks.
--
-- Run after 0012_dashboard_analytics.sql.
-- ============================================================


-- ─── SINGLE-VALUE FIELDS ─────────────────────────────────────

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS campus            TEXT,
  ADD COLUMN IF NOT EXISTS enrolment_year    INT,
  ADD COLUMN IF NOT EXISTS field_of_work     TEXT,
  ADD COLUMN IF NOT EXISTS github_url        TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_url      TEXT,
  ADD COLUMN IF NOT EXISTS credly_url        TEXT,
  ADD COLUMN IF NOT EXISTS career_interests  TEXT,
  ADD COLUMN IF NOT EXISTS company_description TEXT;

COMMENT ON COLUMN profiles.field_of_work IS
  'Alumni equivalent of `course` — §2.3 asks for "programme of study '
  '(students) or current field of work (alumni)".';

COMMENT ON COLUMN profiles.company_description IS
  'Distinct from talent_description: one says what the company does, the '
  'other says who it wants to hire. §2.3 asks for both.';

-- Richfield's campuses, as a hint for the picker rather than a constraint —
-- a CHECK here would mean a migration every time the institution opens or
-- renames one.
COMMENT ON COLUMN profiles.campus IS
  'Campus attended (§2.3). Free text on purpose; the app offers a list.';


-- ─── ENTREPRENEURIAL EXPERIENCE ──────────────────────────────
-- Same shape as employment, different heading.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'experience_kind') THEN
    CREATE TYPE experience_kind AS ENUM ('EMPLOYMENT', 'VENTURE');
  END IF;
END
$$;

ALTER TABLE work_experience
  ADD COLUMN IF NOT EXISTS kind experience_kind NOT NULL DEFAULT 'EMPLOYMENT',
  ADD COLUMN IF NOT EXISTS url  TEXT;

COMMENT ON COLUMN work_experience.kind IS
  'VENTURE covers §2.3''s "businesses founded, start-ups, freelance work, '
  'innovations, or business ventures".';


-- ─── PORTFOLIO ENTRIES ───────────────────────────────────────
-- One table for the two portfolio lists §2.3 asks for — GitHub repositories
-- and deployed sites/apps. They carry identical fields and differ only in
-- what the link points at, so `kind` separates them.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'portfolio_kind') THEN
    CREATE TYPE portfolio_kind AS ENUM ('REPO', 'LIVE_APP');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS portfolio_items (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  kind        portfolio_kind NOT NULL DEFAULT 'REPO',
  title       TEXT NOT NULL,
  url         TEXT NOT NULL,
  description TEXT,
  tech        TEXT[],
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_portfolio_user
  ON portfolio_items(user_id, kind, created_at DESC);


-- ─── CREDENTIALS ─────────────────────────────────────────────
-- Digital badges and professional certifications. §2.3 lists them
-- separately but they are the same record — an issuer, a name, a date and a
-- link — so `kind` again rather than two near-identical tables.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'credential_kind') THEN
    CREATE TYPE credential_kind AS ENUM ('BADGE', 'CERTIFICATION');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS credentials (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  kind        credential_kind NOT NULL DEFAULT 'CERTIFICATION',
  title       TEXT NOT NULL,
  issuer      TEXT,
  issued_on   DATE,
  expires_on  DATE,
  url         TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_credentials_user
  ON credentials(user_id, kind, issued_on DESC);


-- ─── ACHIEVEMENTS, LEADERSHIP AND ACTIVITIES ─────────────────
-- §2.3 lists three: academic achievements/scholarships/awards; leadership
-- roles (SRC, class rep, mentor, ambassador); and participation in clubs,
-- societies, hackathons, competitions, volunteering. Structurally identical
-- — a title, an organisation, a period, a description — so one table with a
-- kind, which also means the profile can render them as three sections from
-- a single query.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'highlight_kind') THEN
    CREATE TYPE highlight_kind AS ENUM ('ACHIEVEMENT', 'LEADERSHIP', 'ACTIVITY');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS profile_highlights (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  kind         highlight_kind NOT NULL,
  title        TEXT NOT NULL,
  organisation TEXT,
  description  TEXT,
  started_on   DATE,
  ended_on     DATE,
  url          TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_highlights_user
  ON profile_highlights(user_id, kind, started_on DESC);


-- ─── RLS ─────────────────────────────────────────────────────
-- All three follow the same rule the existing profile children use: a
-- portfolio is meant to be read, so SELECT is open and writes are owner-only.
-- Anything the owner wants hidden is handled by the section toggles from
-- 0011, which strip server-side.

ALTER TABLE portfolio_items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE credentials        ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_highlights ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['portfolio_items', 'credentials', 'profile_highlights']
  LOOP
    EXECUTE FORMAT('DROP POLICY IF EXISTS %I ON %I', t || '_select', t);
    EXECUTE FORMAT(
      'CREATE POLICY %I ON %I FOR SELECT USING (TRUE)', t || '_select', t);

    EXECUTE FORMAT('DROP POLICY IF EXISTS %I ON %I', t || '_insert_own', t);
    EXECUTE FORMAT(
      'CREATE POLICY %I ON %I FOR INSERT WITH CHECK (user_id = auth.uid())',
      t || '_insert_own', t);

    EXECUTE FORMAT('DROP POLICY IF EXISTS %I ON %I', t || '_update_own', t);
    EXECUTE FORMAT(
      'CREATE POLICY %I ON %I FOR UPDATE USING (user_id = auth.uid() OR is_admin())',
      t || '_update_own', t);

    EXECUTE FORMAT('DROP POLICY IF EXISTS %I ON %I', t || '_delete_own', t);
    EXECUTE FORMAT(
      'CREATE POLICY %I ON %I FOR DELETE USING (user_id = auth.uid() OR is_admin())',
      t || '_delete_own', t);
  END LOOP;
END
$$;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON portfolio_items, credentials, profile_highlights
  TO authenticated;


-- ─── COMPLETENESS ────────────────────────────────────────────
-- profile_completeness drives the student dashboard's "how you compare to
-- your programme" metric, so it has to notice the new sections or a fully
-- filled portfolio still reads as an empty profile.
--
-- Reweighted rather than extended: the old scale already reached 100 with
-- five fields, so adding more without rebalancing would cap everyone.

CREATE OR REPLACE FUNCTION profiles_before_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE score INT := 0;
BEGIN
  IF NOT is_admin() THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'Only administrators can change an account role';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'Only administrators can change an account status';
    END IF;
    IF NEW.email IS DISTINCT FROM OLD.email THEN
      RAISE EXCEPTION 'Email is managed by Supabase Auth';
    END IF;
  END IF;

  -- The basics: 40.
  score :=
    (CASE WHEN NEW.full_name    IS NOT NULL AND NEW.full_name <> '' THEN 6 ELSE 0 END) +
    (CASE WHEN NEW.avatar_url   IS NOT NULL THEN 10 ELSE 0 END) +
    (CASE WHEN NEW.headline     IS NOT NULL AND NEW.headline <> ''  THEN 6 ELSE 0 END) +
    (CASE WHEN NEW.bio          IS NOT NULL AND NEW.bio <> ''       THEN 6 ELSE 0 END) +
    (CASE WHEN NEW.cv_url       IS NOT NULL THEN 8 ELSE 0 END) +
    (CASE WHEN NEW.career_interests IS NOT NULL AND NEW.career_interests <> '' THEN 4 ELSE 0 END);

  -- Links: 15.
  score := score +
    (CASE WHEN NEW.github_url    IS NOT NULL THEN 5 ELSE 0 END) +
    (CASE WHEN NEW.linkedin_url  IS NOT NULL THEN 4 ELSE 0 END) +
    (CASE WHEN NEW.portfolio_url IS NOT NULL THEN 3 ELSE 0 END) +
    (CASE WHEN NEW.credly_url    IS NOT NULL THEN 3 ELSE 0 END);

  -- Substance: 45.
  score := score + LEAST((SELECT COUNT(*) * 3 FROM skills             WHERE user_id = NEW.id)::INT, 15);
  score := score + LEAST((SELECT COUNT(*) * 5 FROM work_experience    WHERE user_id = NEW.id)::INT, 10);
  score := score + LEAST((SELECT COUNT(*) * 4 FROM portfolio_items    WHERE user_id = NEW.id)::INT, 12);
  score := score + LEAST((SELECT COUNT(*) * 3 FROM credentials        WHERE user_id = NEW.id)::INT, 4);
  score := score + LEAST((SELECT COUNT(*) * 2 FROM profile_highlights WHERE user_id = NEW.id)::INT, 4);

  NEW.profile_completeness := LEAST(score, 100);
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$fn$;

-- The new child tables have to poke the profile too, or adding a project
-- leaves completeness stale until the next unrelated profile edit.
DROP TRIGGER IF EXISTS trg_portfolio_touch ON portfolio_items;
CREATE TRIGGER trg_portfolio_touch
  AFTER INSERT OR DELETE ON portfolio_items
  FOR EACH ROW EXECUTE FUNCTION touch_owner_profile();

DROP TRIGGER IF EXISTS trg_credentials_touch ON credentials;
CREATE TRIGGER trg_credentials_touch
  AFTER INSERT OR DELETE ON credentials
  FOR EACH ROW EXECUTE FUNCTION touch_owner_profile();

DROP TRIGGER IF EXISTS trg_highlights_touch ON profile_highlights;
CREATE TRIGGER trg_highlights_touch
  AFTER INSERT OR DELETE ON profile_highlights
  FOR EACH ROW EXECUTE FUNCTION touch_owner_profile();

-- Recompute for everyone who already exists.
UPDATE profiles SET updated_at = NOW();


-- ─── CAREER PATHWAY EXPLORER (§2.5) ──────────────────────────
-- The 0001 `career_pathways` view was never reachable from the app, and as
-- a view it cannot take the caller's programme as an argument. §2.5 asks
-- for "the career trajectories of alumni who studied the same programme",
-- which is a query with a parameter.
--
-- SECURITY DEFINER so it can read work_experience across users and still
-- apply the visibility rules itself — the same reasoning as
-- leaderboard_rows() in 0010.

CREATE OR REPLACE FUNCTION career_pathway(p_course TEXT DEFAULT NULL)
RETURNS TABLE (
  id              UUID,
  full_name       TEXT,
  avatar_url      TEXT,
  course          TEXT,
  graduation_year INT,
  headline        TEXT,
  field_of_work   TEXT,
  roles           JSONB
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT p.id,
         p.full_name,
         p.avatar_url,
         p.course,
         p.graduation_year,
         p.headline,
         p.field_of_work,
         COALESCE(
           (SELECT JSONB_AGG(
                     JSONB_BUILD_OBJECT(
                       'title', w.title,
                       'company', w.company,
                       'start_date', w.start_date,
                       'end_date', w.end_date,
                       'kind', w.kind
                     ) ORDER BY w.start_date DESC NULLS LAST)
              FROM work_experience w WHERE w.user_id = p.id),
           '[]'::JSONB
         ) AS roles
    FROM profiles p
   WHERE p.role = 'ALUMNI'
     AND p.status = 'ACTIVE'
     -- Default to the caller's own programme, which is the question the
     -- screen is actually asking.
     AND p.course IS NOT DISTINCT FROM
         COALESCE(p_course, (SELECT course FROM profiles WHERE id = auth.uid()))
     AND (
       p.id = auth.uid()
       OR is_admin()
       OR CASE WHEN my_role() = 'BUSINESS'
               THEN p.visibility_business
               ELSE p.visibility_peers
          END
     )
   ORDER BY p.graduation_year DESC NULLS LAST, p.full_name;
$fn$;

GRANT EXECUTE ON FUNCTION career_pathway(TEXT) TO authenticated;

-- Which programmes have alumni to explore, for the picker.
CREATE OR REPLACE FUNCTION career_pathway_courses()
RETURNS TABLE (course TEXT, alumni BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT p.course, COUNT(*)
    FROM profiles p
   WHERE p.role = 'ALUMNI' AND p.status = 'ACTIVE' AND p.course IS NOT NULL
   GROUP BY p.course
   ORDER BY COUNT(*) DESC, p.course;
$fn$;

GRANT EXECUTE ON FUNCTION career_pathway_courses() TO authenticated;
