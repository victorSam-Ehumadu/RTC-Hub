-- ============================================================
-- RichConnect / RTC Hub — Supabase PostgreSQL Schema
-- Run this entire file in the Supabase SQL Editor
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- for fuzzy/NLP skill search

-- ─── ENUMS ───────────────────────────────────────────────────
CREATE TYPE user_role       AS ENUM ('STUDENT','ALUMNI','BUSINESS','ADMIN');
CREATE TYPE account_status  AS ENUM ('PENDING','ACTIVE','SUSPENDED','REJECTED');
CREATE TYPE post_type       AS ENUM ('TEXT','CODE','VIDEO','BOUNTY');
CREATE TYPE opportunity_type AS ENUM ('INTERNSHIP','LEARNERSHIP','PART_TIME','GRADUATE');
CREATE TYPE connection_status AS ENUM ('PENDING','ACCEPTED','DECLINED');
CREATE TYPE notif_type      AS ENUM (
  'CONNECTION_REQUEST','CONNECTION_ACCEPTED','NEW_MESSAGE',
  'POST_REACTION','POST_COMMENT','OPPORTUNITY_MATCH',
  'ADMIN_ANNOUNCEMENT','ACCOUNT_APPROVED','ACCOUNT_SUSPENDED',
  'BOUNTY_SOLVED','SKILL_ENDORSED'
);
CREATE TYPE faculty_type    AS ENUM ('IT','BUSINESS');

-- ─── PROFILES (extends Supabase auth.users) ──────────────────
CREATE TABLE profiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role                user_role        NOT NULL DEFAULT 'STUDENT',
  status              account_status   NOT NULL DEFAULT 'PENDING',
  full_name           TEXT             NOT NULL,
  email               TEXT             NOT NULL UNIQUE,
  student_number      TEXT,
  avatar_url          TEXT,
  bio                 TEXT,
  -- Student / Alumni fields
  faculty             faculty_type,
  course              TEXT,
  academic_year       TEXT,
  graduation_year     INT,
  -- Business fields
  company_name        TEXT,
  industry            TEXT,
  company_location    TEXT,
  talent_description  TEXT,
  -- Verification
  verification_photo_url TEXT,
  cv_url              TEXT,
  portfolio_url       TEXT,
  -- Profile completeness (0–100)
  profile_completeness INT DEFAULT 0,
  -- Privacy
  visibility_business BOOLEAN DEFAULT TRUE,  -- show to business users
  visibility_peers    BOOLEAN DEFAULT TRUE,  -- show to students/alumni
  -- Timestamps
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ─── SKILLS ──────────────────────────────────────────────────
CREATE TABLE skills (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  verified   BOOLEAN DEFAULT FALSE,  -- verified via module completion
  module_ref TEXT,                   -- e.g. "Advanced Java"
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, name)
);

-- ─── SKILL ENDORSEMENTS ──────────────────────────────────────
CREATE TABLE skill_endorsements (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  skill_id    UUID NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
  endorser_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  note        TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(skill_id, endorser_id)
);

-- ─── WORK EXPERIENCE ─────────────────────────────────────────
CREATE TABLE work_experience (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  company     TEXT NOT NULL,
  start_date  DATE,
  end_date    DATE,
  description TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── CONNECTIONS ─────────────────────────────────────────────
CREATE TABLE connections (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status      connection_status NOT NULL DEFAULT 'PENDING',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(sender_id, receiver_id),
  CHECK(sender_id <> receiver_id)
);

-- ─── POSTS ───────────────────────────────────────────────────
CREATE TABLE posts (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type            post_type NOT NULL DEFAULT 'TEXT',
  content         TEXT NOT NULL,
  code_language   TEXT,               -- for CODE posts
  code_snippet    TEXT,               -- runnable code
  video_url       TEXT,               -- processed video URL
  thumbnail_url   TEXT,               -- generated thumbnail
  is_flagged      BOOLEAN DEFAULT FALSE,
  flag_reason     TEXT,
  -- Bounty fields
  is_bounty       BOOLEAN DEFAULT FALSE,
  bounty_points   INT DEFAULT 0,
  bounty_solved   BOOLEAN DEFAULT FALSE,
  bounty_module   TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─── POST REACTIONS ──────────────────────────────────────────
CREATE TABLE post_reactions (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id    UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  emoji      TEXT NOT NULL DEFAULT '👍',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

-- ─── COMMENTS ────────────────────────────────────────────────
CREATE TABLE comments (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id       UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  content       TEXT NOT NULL,
  is_solution   BOOLEAN DEFAULT FALSE,  -- marks a bounty solution
  parent_id     UUID REFERENCES comments(id),  -- for threaded replies
  is_flagged    BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ─── DIRECT MESSAGES ─────────────────────────────────────────
CREATE TABLE messages (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  content     TEXT NOT NULL,
  read        BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── NOTIFICATIONS ───────────────────────────────────────────
CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type        notif_type NOT NULL,
  title       TEXT NOT NULL,
  body        TEXT,
  data        JSONB,                    -- extra metadata (post_id, sender_id, etc.)
  read        BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── OPPORTUNITIES ───────────────────────────────────────────
CREATE TABLE opportunities (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  business_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title            TEXT NOT NULL,
  description      TEXT NOT NULL,
  type             opportunity_type NOT NULL,
  location         TEXT,
  remote           BOOLEAN DEFAULT FALSE,
  required_skills  TEXT[],
  required_faculty faculty_type,
  required_year    TEXT,
  status           account_status NOT NULL DEFAULT 'PENDING',  -- admin must approve
  expires_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ─── OPPORTUNITY APPLICATIONS ────────────────────────────────
CREATE TABLE opportunity_applications (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  opportunity_id   UUID NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  applicant_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  cover_note       TEXT,
  status           TEXT DEFAULT 'APPLIED',   -- APPLIED, SHORTLISTED, REJECTED
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(opportunity_id, applicant_id)
);

-- ─── EVENTS (admin-created) ───────────────────────────────────
CREATE TABLE events (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  description  TEXT,
  event_date   TIMESTAMPTZ NOT NULL,
  location     TEXT,
  virtual_link TEXT,
  target_roles user_role[],            -- which user types see the event
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─── ANNOUNCEMENTS ───────────────────────────────────────────
CREATE TABLE announcements (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  body         TEXT NOT NULL,
  target_roles user_role[],            -- NULL = all users
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─── MENTORSHIP (Shadow-a-Senior) ────────────────────────────
CREATE TABLE mentorship_subscriptions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mentor_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  mentee_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(mentor_id, mentee_id)
);

-- ─── LEGACY ARCHIVES ─────────────────────────────────────────
CREATE TABLE legacy_archives (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  description TEXT,
  content     TEXT,                    -- markdown / rich text
  course      TEXT,
  tags        TEXT[],
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── LOGIC POINTS (Bounty system) ────────────────────────────
CREATE TABLE logic_points (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount     INT NOT NULL,
  reason     TEXT,
  post_id    UUID REFERENCES posts(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── PROFILE ANALYTICS (daily snapshots) ────────────────────
CREATE TABLE profile_analytics (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  date         DATE NOT NULL,
  profile_views INT DEFAULT 0,
  post_views   INT DEFAULT 0,
  post_reactions INT DEFAULT 0,
  new_connections INT DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, date)
);

-- ─── ONBOARDING PROGRESS ────────────────────────────────────
CREATE TABLE onboarding_progress (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  tutorial_complete BOOLEAN DEFAULT FALSE,
  profile_step      INT DEFAULT 0,       -- which onboarding step they're on
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ─── ADMIN CONTENT FLAGS ─────────────────────────────────────
CREATE TABLE content_flags (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reporter_id  UUID NOT NULL REFERENCES profiles(id),
  post_id      UUID REFERENCES posts(id),
  comment_id   UUID REFERENCES comments(id),
  user_id      UUID REFERENCES profiles(id),   -- flagging an account
  reason       TEXT NOT NULL,
  resolved     BOOLEAN DEFAULT FALSE,
  resolved_by  UUID REFERENCES profiles(id),
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─── VIEWS ───────────────────────────────────────────────────
-- Leaderboard view (top contributors by logic points)
CREATE OR REPLACE VIEW leaderboard AS
SELECT
  p.id,
  p.full_name,
  p.avatar_url,
  p.course,
  p.faculty,
  COALESCE(SUM(lp.amount), 0) AS total_points,
  COUNT(DISTINCT s.id) AS skill_count
FROM profiles p
LEFT JOIN logic_points lp ON lp.user_id = p.id
LEFT JOIN skills s ON s.user_id = p.id
WHERE p.role IN ('STUDENT','ALUMNI') AND p.status = 'ACTIVE'
GROUP BY p.id, p.full_name, p.avatar_url, p.course, p.faculty
ORDER BY total_points DESC;

-- Career pathway view (alumni trajectories by course)
CREATE OR REPLACE VIEW career_pathways AS
SELECT
  p.course,
  p.graduation_year,
  p.full_name,
  p.avatar_url,
  p.bio,
  ARRAY_AGG(DISTINCT s.name) AS skills,
  ARRAY_AGG(DISTINCT we.title || ' @ ' || we.company ORDER BY we.title || ' @ ' || we.company) AS roles
FROM profiles p
LEFT JOIN skills s ON s.user_id = p.id
LEFT JOIN work_experience we ON we.user_id = p.id
WHERE p.role = 'ALUMNI' AND p.status = 'ACTIVE'
GROUP BY p.id, p.course, p.graduation_year, p.full_name, p.avatar_url, p.bio;

-- ─── FUNCTIONS ───────────────────────────────────────────────

-- Auto-update profile completeness
CREATE OR REPLACE FUNCTION compute_profile_completeness(uid UUID)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE score INT := 0;
BEGIN
  SELECT
    (CASE WHEN full_name IS NOT NULL AND full_name <> '' THEN 10 ELSE 0 END) +
    (CASE WHEN avatar_url IS NOT NULL THEN 15 ELSE 0 END) +
    (CASE WHEN bio IS NOT NULL AND bio <> '' THEN 10 ELSE 0 END) +
    (CASE WHEN cv_url IS NOT NULL THEN 15 ELSE 0 END) +
    (CASE WHEN portfolio_url IS NOT NULL THEN 10 ELSE 0 END)
  INTO score FROM profiles WHERE id = uid;

  -- Skills bonus (up to 20)
  score := score + LEAST((SELECT COUNT(*) * 4 FROM skills WHERE user_id = uid)::INT, 20);
  -- Experience bonus (up to 20)
  score := score + LEAST((SELECT COUNT(*) * 10 FROM work_experience WHERE user_id = uid)::INT, 20);

  UPDATE profiles SET profile_completeness = score, updated_at = NOW() WHERE id = uid;
  RETURN score;
END;
$$;

-- Escalate bounty points over time (run via pg_cron or manual cron)
CREATE OR REPLACE FUNCTION escalate_bounties()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE posts
  SET bounty_points = LEAST(bounty_points + 5, 500)
  WHERE is_bounty = TRUE
    AND bounty_solved = FALSE
    AND created_at < NOW() - INTERVAL '24 hours';
END;
$$;

-- Auto-update updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_profiles_updated     BEFORE UPDATE ON profiles     FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_posts_updated        BEFORE UPDATE ON posts        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_opportunities_updated BEFORE UPDATE ON opportunities FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_connections_updated  BEFORE UPDATE ON connections   FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── ROW LEVEL SECURITY ──────────────────────────────────────
ALTER TABLE profiles                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE skills                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE skill_endorsements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_experience           ENABLE ROW LEVEL SECURITY;
ALTER TABLE connections               ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_reactions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications             ENABLE ROW LEVEL SECURITY;
ALTER TABLE opportunities             ENABLE ROW LEVEL SECURITY;
ALTER TABLE opportunity_applications  ENABLE ROW LEVEL SECURITY;
ALTER TABLE events                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements             ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_subscriptions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE legacy_archives           ENABLE ROW LEVEL SECURITY;
ALTER TABLE logic_points              ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_analytics         ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_progress       ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_flags             ENABLE ROW LEVEL SECURITY;

-- Helper: check if user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN');
$$;

-- Profiles: users see own profile, admins see all, active users see others
CREATE POLICY "profiles_select" ON profiles FOR SELECT
  USING (id = auth.uid() OR is_admin() OR status = 'ACTIVE');
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE
  USING (id = auth.uid() OR is_admin());
CREATE POLICY "profiles_insert" ON profiles FOR INSERT
  WITH CHECK (id = auth.uid());

-- Skills: own + public reads
CREATE POLICY "skills_all_own" ON skills FOR ALL USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "skills_select_public" ON skills FOR SELECT USING (TRUE);

-- Posts: active users can read non-flagged, authors manage own
CREATE POLICY "posts_select" ON posts FOR SELECT USING (is_flagged = FALSE OR author_id = auth.uid() OR is_admin());
CREATE POLICY "posts_insert" ON posts FOR INSERT WITH CHECK (author_id = auth.uid());
CREATE POLICY "posts_update_own" ON posts FOR UPDATE USING (author_id = auth.uid() OR is_admin());
CREATE POLICY "posts_delete_own" ON posts FOR DELETE USING (author_id = auth.uid() OR is_admin());

-- Messages: only sender and receiver
CREATE POLICY "messages_select" ON messages FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid());
CREATE POLICY "messages_insert" ON messages FOR INSERT WITH CHECK (sender_id = auth.uid());

-- Notifications: own only
CREATE POLICY "notifications_own" ON notifications FOR ALL USING (user_id = auth.uid() OR is_admin());

-- Opportunities: business owners manage, approved ones visible to all
CREATE POLICY "opps_select" ON opportunities FOR SELECT USING (status = 'ACTIVE' OR business_id = auth.uid() OR is_admin());
CREATE POLICY "opps_insert" ON opportunities FOR INSERT WITH CHECK (business_id = auth.uid());
CREATE POLICY "opps_update" ON opportunities FOR UPDATE USING (business_id = auth.uid() OR is_admin());

-- Events: all active users can view
CREATE POLICY "events_select" ON events FOR SELECT USING (TRUE);
CREATE POLICY "events_all_admin" ON events FOR ALL USING (is_admin());

-- Announcements: all can read
CREATE POLICY "annc_select" ON announcements FOR SELECT USING (TRUE);
CREATE POLICY "annc_all_admin" ON announcements FOR ALL USING (is_admin());

-- Connections
CREATE POLICY "conn_select" ON connections FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid() OR is_admin());
CREATE POLICY "conn_insert" ON connections FOR INSERT WITH CHECK (sender_id = auth.uid());
CREATE POLICY "conn_update" ON connections FOR UPDATE USING (receiver_id = auth.uid() OR is_admin());

-- ─── INDEXES ────────────────────────────────────────────────
CREATE INDEX idx_profiles_role       ON profiles(role);
CREATE INDEX idx_profiles_status     ON profiles(status);
CREATE INDEX idx_posts_author        ON posts(author_id);
CREATE INDEX idx_posts_created       ON posts(created_at DESC);
CREATE INDEX idx_messages_conv       ON messages(sender_id, receiver_id);
CREATE INDEX idx_notifications_user  ON notifications(user_id, read);
CREATE INDEX idx_skills_name         ON skills USING gin(name gin_trgm_ops);
CREATE INDEX idx_opportunities_skills ON opportunities USING gin(required_skills);

-- ─── REALTIME ────────────────────────────────────────────────
-- Enable realtime for live notifications and messages
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE posts;
ALTER PUBLICATION supabase_realtime ADD TABLE connections;

-- ─── SEED: Admin account provisioning ────────────────────────
-- IMPORTANT: Create admin user via Supabase Auth dashboard first,
-- then run this INSERT with their UUID.
-- REPLACE 'YOUR-ADMIN-UUID-HERE' with the actual UUID from auth.users
/*
INSERT INTO profiles (id, role, status, full_name, email)
VALUES ('YOUR-ADMIN-UUID-HERE', 'ADMIN', 'ACTIVE', 'Platform Admin', 'admin@richfield.ac.za');
*/