-- ============================================================
-- RTC Hub — 0002: client-direct access
--
-- The Express API used to sit between the app and the database holding a
-- service-role key, so RLS was decorative and privileged work (awarding
-- Logic Points, notifying other users, approving accounts) lived in route
-- handlers. The Flutter app talks straight to Supabase with an anon key,
-- so all of that has to move into the database:
--
--   * RLS policies become the real authorization boundary
--   * privileged writes happen in SECURITY DEFINER triggers / RPCs
--   * anything a client must not forge is simply not writable by them
--
-- Run after 0001_initial_schema.sql.
-- ============================================================

-- ─── SIGNUP: build the profile from auth metadata ────────────
-- Replaces POST /api/auth/signup. The client calls supabase.auth.signUp()
-- with the profile fields in `data`; this unpacks them. Doing it here rather
-- than as a client INSERT keeps role/status out of the client's hands and
-- makes signup atomic — no orphaned auth user if the profile write fails.
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

  -- Richfield domain + 9-digit student number enforcement.
  IF want_role = 'STUDENT' THEN
    IF clean_email NOT LIKE '%@my.richfield.ac.za'
       AND clean_email NOT LIKE '%@richfield.ac.za' THEN
      RAISE EXCEPTION 'Student registration requires a @richfield.ac.za email address';
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

  -- Queue the account for admin review.
  IF new_status = 'PENDING' THEN
    INSERT INTO notifications (user_id, type, title, body, data)
    SELECT p.id, 'ACCOUNT_APPROVED',
           'New account pending approval',
           display || ' registered as ' || want_role || ' and needs review.',
           JSONB_BUILD_OBJECT('pending_user_id', NEW.id)
    FROM profiles p WHERE p.role = 'ADMIN';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_auth_user_created ON auth.users;
CREATE TRIGGER trg_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ─── PROFILE GUARD: block privilege escalation ───────────────
-- profiles_update_own lets a user UPDATE their own row, which without this
-- guard would let any student set role='ADMIN' or status='ACTIVE'.
-- profile_completeness is derived, so it is recomputed here and never
-- accepted from the client.
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

  score :=
    (CASE WHEN NEW.full_name     IS NOT NULL AND NEW.full_name <> '' THEN 10 ELSE 0 END) +
    (CASE WHEN NEW.avatar_url    IS NOT NULL THEN 15 ELSE 0 END) +
    (CASE WHEN NEW.bio           IS NOT NULL AND NEW.bio <> ''       THEN 10 ELSE 0 END) +
    (CASE WHEN NEW.cv_url        IS NOT NULL THEN 15 ELSE 0 END) +
    (CASE WHEN NEW.portfolio_url IS NOT NULL THEN 10 ELSE 0 END);
  score := score + LEAST((SELECT COUNT(*) * 4  FROM skills          WHERE user_id = NEW.id)::INT, 20);
  score := score + LEAST((SELECT COUNT(*) * 10 FROM work_experience WHERE user_id = NEW.id)::INT, 20);

  NEW.profile_completeness := score;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_profiles_guard ON profiles;
CREATE TRIGGER trg_profiles_guard
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION profiles_before_update();

-- Adding a skill or a job changes completeness; poke the profile so the
-- trigger above recomputes it.
CREATE OR REPLACE FUNCTION touch_owner_profile()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  UPDATE profiles SET updated_at = NOW()
  WHERE id = COALESCE(NEW.user_id, OLD.user_id);
  RETURN COALESCE(NEW, OLD);
END;
$fn$;

DROP TRIGGER IF EXISTS trg_skills_touch ON skills;
CREATE TRIGGER trg_skills_touch
  AFTER INSERT OR DELETE ON skills
  FOR EACH ROW EXECUTE FUNCTION touch_owner_profile();

DROP TRIGGER IF EXISTS trg_work_touch ON work_experience;
CREATE TRIGGER trg_work_touch
  AFTER INSERT OR DELETE ON work_experience
  FOR EACH ROW EXECUTE FUNCTION touch_owner_profile();

-- ─── NOTIFICATIONS: fan-out the client cannot do itself ──────
-- The notifications_own policy deliberately blocks writing rows for other
-- users, so every cross-user notification is raised by a trigger here.
CREATE OR REPLACE FUNCTION notify(
  target UUID, kind notif_type, title TEXT, body TEXT, payload JSONB DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF target IS NULL THEN RETURN; END IF;
  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (target, kind, title, body, payload);
END;
$fn$;

CREATE OR REPLACE FUNCTION on_reaction_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE author UUID; actor TEXT;
BEGIN
  SELECT author_id INTO author FROM posts WHERE id = NEW.post_id;
  IF author IS NULL OR author = NEW.user_id THEN RETURN NEW; END IF;
  SELECT full_name INTO actor FROM profiles WHERE id = NEW.user_id;
  PERFORM notify(author, 'POST_REACTION', 'Someone reacted to your post',
                 actor || ' reacted ' || NEW.emoji || ' to your post.',
                 JSONB_BUILD_OBJECT('post_id', NEW.post_id, 'reactor_id', NEW.user_id));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_reaction_notify ON post_reactions;
CREATE TRIGGER trg_reaction_notify
  AFTER INSERT ON post_reactions
  FOR EACH ROW EXECUTE FUNCTION on_reaction_created();

CREATE OR REPLACE FUNCTION on_comment_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE author UUID; actor TEXT;
BEGIN
  SELECT author_id INTO author FROM posts WHERE id = NEW.post_id;
  IF author IS NULL OR author = NEW.author_id THEN RETURN NEW; END IF;
  SELECT full_name INTO actor FROM profiles WHERE id = NEW.author_id;
  PERFORM notify(author, 'POST_COMMENT', 'New comment on your post',
                 actor || ': ' || LEFT(NEW.content, 80),
                 JSONB_BUILD_OBJECT('post_id', NEW.post_id, 'comment_id', NEW.id));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_comment_notify ON comments;
CREATE TRIGGER trg_comment_notify
  AFTER INSERT ON comments
  FOR EACH ROW EXECUTE FUNCTION on_comment_created();

CREATE OR REPLACE FUNCTION on_message_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE actor TEXT;
BEGIN
  SELECT full_name INTO actor FROM profiles WHERE id = NEW.sender_id;
  PERFORM notify(NEW.receiver_id, 'NEW_MESSAGE', 'Message from ' || actor,
                 LEFT(NEW.content, 80),
                 JSONB_BUILD_OBJECT('sender_id', NEW.sender_id, 'message_id', NEW.id));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_message_notify ON messages;
CREATE TRIGGER trg_message_notify
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION on_message_created();

CREATE OR REPLACE FUNCTION on_connection_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE actor TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT full_name INTO actor FROM profiles WHERE id = NEW.sender_id;
    PERFORM notify(NEW.receiver_id, 'CONNECTION_REQUEST', 'New connection request',
                   actor || ' wants to connect with you.',
                   JSONB_BUILD_OBJECT('connection_id', NEW.id, 'sender_id', NEW.sender_id));
  ELSIF NEW.status = 'ACCEPTED' AND OLD.status IS DISTINCT FROM 'ACCEPTED' THEN
    SELECT full_name INTO actor FROM profiles WHERE id = NEW.receiver_id;
    PERFORM notify(NEW.sender_id, 'CONNECTION_ACCEPTED', 'Connection accepted',
                   actor || ' accepted your connection request.',
                   JSONB_BUILD_OBJECT('connection_id', NEW.id, 'user_id', NEW.receiver_id));
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_connection_notify ON connections;
CREATE TRIGGER trg_connection_notify
  AFTER INSERT OR UPDATE ON connections
  FOR EACH ROW EXECUTE FUNCTION on_connection_change();

-- Account approval / suspension, so the user finds out.
CREATE OR REPLACE FUNCTION on_profile_status_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'ACTIVE' THEN
      PERFORM notify(NEW.id, 'ACCOUNT_APPROVED', 'Your account was approved',
                     'Welcome to RTC Hub — your account is now active.', NULL);
    ELSIF NEW.status IN ('SUSPENDED', 'REJECTED') THEN
      PERFORM notify(NEW.id, 'ACCOUNT_SUSPENDED',
                     'Your account was ' || LOWER(NEW.status::TEXT),
                     'Contact a Richfield administrator for details.', NULL);
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_profile_status_notify ON profiles;
CREATE TRIGGER trg_profile_status_notify
  AFTER UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION on_profile_status_change();

CREATE OR REPLACE FUNCTION on_skill_endorsed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE owner_id UUID; skill_name TEXT; actor TEXT;
BEGIN
  SELECT user_id, name INTO owner_id, skill_name FROM skills WHERE id = NEW.skill_id;
  IF owner_id IS NULL OR owner_id = NEW.endorser_id THEN RETURN NEW; END IF;
  SELECT full_name INTO actor FROM profiles WHERE id = NEW.endorser_id;
  PERFORM notify(owner_id, 'SKILL_ENDORSED', 'Skill endorsed',
                 actor || ' endorsed your ' || skill_name || ' skill.',
                 JSONB_BUILD_OBJECT('skill_id', NEW.skill_id, 'endorser_id', NEW.endorser_id));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_endorsement_notify ON skill_endorsements;
CREATE TRIGGER trg_endorsement_notify
  AFTER INSERT ON skill_endorsements
  FOR EACH ROW EXECUTE FUNCTION on_skill_endorsed();

-- ─── BOUNTIES: accepting a solution pays out ─────────────────
-- The old API let the *commenter* pass is_solution:true and award themselves
-- the points. Only the person who posted the bounty may accept an answer, so
-- is_solution is frozen against direct writes (see the comments policies)
-- and the payout runs here.
CREATE OR REPLACE FUNCTION accept_bounty_solution(p_comment_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE c RECORD; p RECORD;
BEGIN
  SELECT * INTO c FROM comments WHERE id = p_comment_id;
  IF c IS NULL THEN RAISE EXCEPTION 'Comment not found'; END IF;

  SELECT * INTO p FROM posts WHERE id = c.post_id;
  IF p IS NULL THEN RAISE EXCEPTION 'Post not found'; END IF;
  IF NOT p.is_bounty THEN RAISE EXCEPTION 'That post is not a bounty'; END IF;
  IF p.author_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the person who posted the bounty can accept a solution';
  END IF;
  IF p.bounty_solved THEN RAISE EXCEPTION 'This bounty has already been solved'; END IF;
  IF c.author_id = p.author_id THEN RAISE EXCEPTION 'You cannot accept your own answer'; END IF;

  UPDATE comments SET is_solution = TRUE WHERE id = p_comment_id;
  UPDATE posts    SET bounty_solved = TRUE WHERE id = p.id;

  INSERT INTO logic_points (user_id, amount, reason, post_id)
  VALUES (c.author_id, p.bounty_points, 'Solved bounty: ' || LEFT(p.content, 50), p.id);

  PERFORM notify(c.author_id, 'BOUNTY_SOLVED',
                 'You earned ' || p.bounty_points || ' Logic Points!',
                 'Your answer was accepted as the bounty solution.',
                 JSONB_BUILD_OBJECT('post_id', p.id, 'points', p.bounty_points));
END;
$fn$;

-- Bounty posts open at 10 points; clients do not set their own price, and
-- moderation flags are an admin-only field.
CREATE OR REPLACE FUNCTION posts_before_write()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.bounty_points := CASE WHEN NEW.is_bounty THEN 10 ELSE 0 END;
    NEW.bounty_solved := FALSE;
    NEW.is_flagged    := FALSE;
    IF NEW.is_bounty THEN NEW.type := 'BOUNTY'; END IF;
  ELSIF NOT is_admin() THEN
    NEW.bounty_points := OLD.bounty_points;   -- only escalate_bounties() moves this
    NEW.bounty_solved := OLD.bounty_solved;   -- only accept_bounty_solution() does
    NEW.is_flagged    := OLD.is_flagged;
    NEW.author_id     := OLD.author_id;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_posts_guard ON posts;
CREATE TRIGGER trg_posts_guard
  BEFORE INSERT OR UPDATE ON posts
  FOR EACH ROW EXECUTE FUNCTION posts_before_write();

-- Same idea for comments: is_solution is set only by accept_bounty_solution().
CREATE OR REPLACE FUNCTION comments_before_write()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.is_solution := FALSE;
    NEW.is_flagged  := FALSE;
  ELSIF NOT is_admin() THEN
    NEW.is_solution := OLD.is_solution;
    NEW.is_flagged  := OLD.is_flagged;
    NEW.author_id   := OLD.author_id;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_comments_guard ON comments;
CREATE TRIGGER trg_comments_guard
  BEFORE INSERT OR UPDATE ON comments
  FOR EACH ROW EXECUTE FUNCTION comments_before_write();

-- Logic Points totals, for the profile header and leaderboard.
CREATE OR REPLACE FUNCTION total_logic_points(uid UUID)
RETURNS INT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT COALESCE(SUM(amount), 0)::INT FROM logic_points WHERE user_id = uid;
$fn$;

-- ─── PROFILE VIEWS (analytics) ───────────────────────────────
CREATE OR REPLACE FUNCTION record_profile_view(target UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF target IS NULL OR target = auth.uid() THEN RETURN; END IF;
  INSERT INTO profile_analytics (user_id, date, profile_views)
  VALUES (target, CURRENT_DATE, 1)
  ON CONFLICT (user_id, date)
  DO UPDATE SET profile_views = profile_analytics.profile_views + 1;
END;
$fn$;

-- ─── ADMIN: broadcast an announcement ────────────────────────
CREATE OR REPLACE FUNCTION broadcast_announcement(
  p_title TEXT, p_body TEXT, p_target_roles user_role[] DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE new_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;

  INSERT INTO announcements (admin_id, title, body, target_roles)
  VALUES (auth.uid(), p_title, p_body, p_target_roles)
  RETURNING id INTO new_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT p.id, 'ADMIN_ANNOUNCEMENT', p_title, p_body,
         JSONB_BUILD_OBJECT('announcement_id', new_id)
  FROM profiles p
  WHERE p.status = 'ACTIVE'
    AND (p_target_roles IS NULL OR p.role = ANY(p_target_roles));

  RETURN new_id;
END;
$fn$;

-- ─── OPPORTUNITY MATCHING ────────────────────────────────────
-- Replaces services/matchingService.js: score the caller against every live
-- opportunity by skill overlap, faculty and year.
CREATE OR REPLACE FUNCTION matched_opportunities()
RETURNS TABLE (opportunity_id UUID, score INT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT o.id,
         (
           SELECT COUNT(*)::INT FROM skills s
           WHERE s.user_id = auth.uid()
             AND o.required_skills IS NOT NULL
             AND LOWER(s.name) = ANY (SELECT LOWER(x) FROM UNNEST(o.required_skills) AS x)
         )
         + CASE WHEN o.required_faculty IS NOT NULL
                 AND o.required_faculty = (SELECT faculty FROM profiles WHERE id = auth.uid())
                THEN 2 ELSE 0 END
         + CASE WHEN o.required_year IS NOT NULL
                 AND o.required_year = (SELECT academic_year FROM profiles WHERE id = auth.uid())
                THEN 1 ELSE 0 END AS score
  FROM opportunities o
  WHERE o.status = 'ACTIVE'
    AND (o.expires_at IS NULL OR o.expires_at > NOW())
  ORDER BY score DESC, o.created_at DESC;
$fn$;

-- Tell matching students when an opportunity goes live.
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
      AND (NEW.required_faculty IS NULL OR p.faculty = NEW.required_faculty);
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_opportunity_activated ON opportunities;
CREATE TRIGGER trg_opportunity_activated
  AFTER UPDATE ON opportunities
  FOR EACH ROW EXECUTE FUNCTION on_opportunity_activated();

-- Businesses do not get to approve their own listings.
CREATE OR REPLACE FUNCTION opportunities_before_write()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN
    IF TG_OP = 'INSERT' THEN
      NEW.status := 'PENDING';
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'Only administrators can change an opportunity status';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_opportunities_guard ON opportunities;
CREATE TRIGGER trg_opportunities_guard
  BEFORE INSERT OR UPDATE ON opportunities
  FOR EACH ROW EXECUTE FUNCTION opportunities_before_write();

-- ============================================================
-- ROW LEVEL SECURITY
--
-- 0001 turned RLS on for every table but only wrote policies for nine of
-- them. RLS with no policy denies everything, so the tables below were
-- unreachable the moment the service-role key went away.
-- ============================================================

-- Profiles ----------------------------------------------------
-- Replaces the 0001 policy so suspended accounts stop being readable and
-- the privacy toggles are honoured.
DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid()
  OR is_admin()
  OR (
    status = 'ACTIVE' AND (
      CASE
        WHEN (SELECT role FROM profiles me WHERE me.id = auth.uid()) = 'BUSINESS'
          THEN visibility_business
        ELSE visibility_peers
      END
    )
  )
);

DROP POLICY IF EXISTS "profiles_delete" ON profiles;
CREATE POLICY "profiles_delete" ON profiles FOR DELETE USING (is_admin());

-- Skills ------------------------------------------------------
-- 0001 had skills_all_own FOR ALL, whose USING clause does not constrain
-- INSERT; spell the write side out explicitly.
DROP POLICY IF EXISTS "skills_all_own" ON skills;
DROP POLICY IF EXISTS "skills_insert_own" ON skills;
DROP POLICY IF EXISTS "skills_update_own" ON skills;
DROP POLICY IF EXISTS "skills_delete_own" ON skills;
CREATE POLICY "skills_insert_own" ON skills FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "skills_update_own" ON skills FOR UPDATE USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "skills_delete_own" ON skills FOR DELETE USING (user_id = auth.uid() OR is_admin());

-- Skill endorsements ------------------------------------------
CREATE POLICY "endorse_select"     ON skill_endorsements FOR SELECT USING (TRUE);
CREATE POLICY "endorse_insert"     ON skill_endorsements FOR INSERT WITH CHECK (endorser_id = auth.uid());
CREATE POLICY "endorse_delete_own" ON skill_endorsements FOR DELETE USING (endorser_id = auth.uid() OR is_admin());

-- Work experience ---------------------------------------------
CREATE POLICY "work_select"     ON work_experience FOR SELECT USING (TRUE);
CREATE POLICY "work_insert_own" ON work_experience FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "work_update_own" ON work_experience FOR UPDATE USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "work_delete_own" ON work_experience FOR DELETE USING (user_id = auth.uid() OR is_admin());

-- Post reactions ----------------------------------------------
CREATE POLICY "reactions_select"     ON post_reactions FOR SELECT USING (TRUE);
CREATE POLICY "reactions_insert_own" ON post_reactions FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "reactions_delete_own" ON post_reactions FOR DELETE USING (user_id = auth.uid() OR is_admin());

-- Comments ----------------------------------------------------
CREATE POLICY "comments_select"     ON comments FOR SELECT USING (is_flagged = FALSE OR author_id = auth.uid() OR is_admin());
CREATE POLICY "comments_insert_own" ON comments FOR INSERT WITH CHECK (author_id = auth.uid());
CREATE POLICY "comments_update_own" ON comments FOR UPDATE USING (author_id = auth.uid() OR is_admin());
CREATE POLICY "comments_delete_own" ON comments FOR DELETE USING (author_id = auth.uid() OR is_admin());

-- Messages ----------------------------------------------------
-- The receiver needs UPDATE to mark a thread read.
CREATE POLICY "messages_update_receiver" ON messages FOR UPDATE
  USING (receiver_id = auth.uid())
  WITH CHECK (receiver_id = auth.uid());
CREATE POLICY "messages_delete_sender" ON messages FOR DELETE
  USING (sender_id = auth.uid() OR is_admin());

-- Notifications -----------------------------------------------
-- 0001's FOR ALL policy has no WITH CHECK, so INSERT was unrestricted and a
-- client could spam any user. Reads/updates stay owner-scoped; all inserts
-- now come from SECURITY DEFINER code, which bypasses RLS.
DROP POLICY IF EXISTS "notifications_own" ON notifications;
CREATE POLICY "notifications_select_own" ON notifications FOR SELECT USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "notifications_update_own" ON notifications FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "notifications_delete_own" ON notifications FOR DELETE USING (user_id = auth.uid() OR is_admin());

-- Opportunities -----------------------------------------------
CREATE POLICY "opps_delete" ON opportunities FOR DELETE USING (business_id = auth.uid() OR is_admin());

-- Opportunity applications ------------------------------------
CREATE POLICY "apps_select" ON opportunity_applications FOR SELECT USING (
  applicant_id = auth.uid()
  OR is_admin()
  OR EXISTS (SELECT 1 FROM opportunities o WHERE o.id = opportunity_id AND o.business_id = auth.uid())
);
CREATE POLICY "apps_insert_own" ON opportunity_applications FOR INSERT WITH CHECK (applicant_id = auth.uid());
CREATE POLICY "apps_update_owner" ON opportunity_applications FOR UPDATE USING (
  is_admin()
  OR EXISTS (SELECT 1 FROM opportunities o WHERE o.id = opportunity_id AND o.business_id = auth.uid())
);
CREATE POLICY "apps_delete_own" ON opportunity_applications FOR DELETE USING (applicant_id = auth.uid() OR is_admin());

-- Mentorship --------------------------------------------------
CREATE POLICY "mentorship_select" ON mentorship_subscriptions FOR SELECT
  USING (mentor_id = auth.uid() OR mentee_id = auth.uid() OR is_admin());
CREATE POLICY "mentorship_insert" ON mentorship_subscriptions FOR INSERT WITH CHECK (mentee_id = auth.uid());
CREATE POLICY "mentorship_delete" ON mentorship_subscriptions FOR DELETE
  USING (mentee_id = auth.uid() OR mentor_id = auth.uid() OR is_admin());

-- Legacy archives ---------------------------------------------
CREATE POLICY "archives_select"     ON legacy_archives FOR SELECT USING (TRUE);
CREATE POLICY "archives_insert_own" ON legacy_archives FOR INSERT WITH CHECK (author_id = auth.uid());
CREATE POLICY "archives_update_own" ON legacy_archives FOR UPDATE USING (author_id = auth.uid() OR is_admin());
CREATE POLICY "archives_delete_own" ON legacy_archives FOR DELETE USING (author_id = auth.uid() OR is_admin());

-- Logic points ------------------------------------------------
-- Read-only to clients on purpose: the ledger is written exclusively by
-- accept_bounty_solution(). No INSERT/UPDATE/DELETE policy exists, so those
-- are denied outright.
CREATE POLICY "points_select_own" ON logic_points FOR SELECT USING (user_id = auth.uid() OR is_admin());

-- Profile analytics -------------------------------------------
-- Written only by record_profile_view().
CREATE POLICY "analytics_select_own" ON profile_analytics FOR SELECT USING (user_id = auth.uid() OR is_admin());

-- Onboarding --------------------------------------------------
CREATE POLICY "onboarding_select_own" ON onboarding_progress FOR SELECT USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "onboarding_update_own" ON onboarding_progress FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Content flags -----------------------------------------------
CREATE POLICY "flags_select" ON content_flags FOR SELECT USING (reporter_id = auth.uid() OR is_admin());
CREATE POLICY "flags_insert" ON content_flags FOR INSERT WITH CHECK (reporter_id = auth.uid());
CREATE POLICY "flags_update_admin" ON content_flags FOR UPDATE USING (is_admin());

-- ─── VIEWS ───────────────────────────────────────────────────
-- Views run as their owner by default, which would leak rows past the
-- policies above. leaderboard already filters to ACTIVE students/alumni so
-- it is safe as-is; career_pathways is switched to the caller's rights.
ALTER VIEW career_pathways SET (security_invoker = ON);

-- ─── STORAGE ─────────────────────────────────────────────────
-- Uploads used to go through POST /api/upload with multer + sharp. The app
-- now writes directly to Storage, so each bucket needs its own policies.
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', TRUE), ('post-media', 'post-media', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', FALSE), ('verification', 'verification', FALSE)
ON CONFLICT (id) DO NOTHING;

-- Convention: every object is stored under a folder named for the owner's
-- uid, so ownership is the first path segment.
DROP POLICY IF EXISTS "public_buckets_read" ON storage.objects;
CREATE POLICY "public_buckets_read" ON storage.objects FOR SELECT
  USING (bucket_id IN ('avatars', 'post-media'));

DROP POLICY IF EXISTS "private_buckets_read_own" ON storage.objects;
CREATE POLICY "private_buckets_read_own" ON storage.objects FOR SELECT
  USING (
    bucket_id IN ('documents', 'verification')
    AND (auth.uid()::TEXT = (storage.foldername(name))[1] OR is_admin())
  );

DROP POLICY IF EXISTS "own_folder_insert" ON storage.objects;
CREATE POLICY "own_folder_insert" ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id IN ('avatars', 'post-media', 'documents', 'verification')
    AND auth.uid()::TEXT = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "own_folder_update" ON storage.objects;
CREATE POLICY "own_folder_update" ON storage.objects FOR UPDATE
  USING (auth.uid()::TEXT = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "own_folder_delete" ON storage.objects;
CREATE POLICY "own_folder_delete" ON storage.objects FOR DELETE
  USING (auth.uid()::TEXT = (storage.foldername(name))[1] OR is_admin());

-- ─── REALTIME ────────────────────────────────────────────────
-- 0001 published messages/notifications/posts/connections. Realtime honours
-- RLS on the subscriber's behalf, so these deliver only rows the user may
-- already read. Comments join them so post detail updates live.
ALTER PUBLICATION supabase_realtime ADD TABLE comments;

-- ─── GRANTS ──────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION accept_bounty_solution(UUID)                   TO authenticated;
GRANT EXECUTE ON FUNCTION total_logic_points(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION record_profile_view(UUID)                      TO authenticated;
GRANT EXECUTE ON FUNCTION broadcast_announcement(TEXT, TEXT, user_role[]) TO authenticated;
GRANT EXECUTE ON FUNCTION matched_opportunities()                        TO authenticated;

-- notify() is an internal helper for the triggers above; keep it off the API.
REVOKE EXECUTE ON FUNCTION notify(UUID, notif_type, TEXT, TEXT, JSONB) FROM authenticated, anon;
