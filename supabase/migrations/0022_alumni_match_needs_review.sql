-- ============================================================
-- RTC Hub — 0022: alumni student-number match is a hint, not auto-approval
--
-- 0020_restore_alumni_auto_verify.sql (already run against the shared
-- project) auto-activates an ALUMNI signup — skipping admin review entirely
-- — whenever the submitted student_number + faculty matches an existing
-- STUDENT row. Neither field is a secret: student_number is the 9-digit
-- prefix of every student's own email address (sequential, guessable within
-- a cohort) and faculty only has two values. Nothing in that check proves the
-- person signing up as ALUMNI is actually the student they're claiming to be
-- — it's an unauthenticated signup matching another profile's public-ish
-- identifiers. As written, anyone can self-activate an ALUMNI account by
-- guessing a plausible student_number, which defeats exactly the control the
-- hackathon guidelines require: role-based access enforced on the backend,
-- with BUSINESS/ALUMNI held PENDING for a human to review.
--
-- The underlying idea — a graduating student shouldn't have to fight through
-- review again — is reasonable; matching on guessable fields alone isn't
-- enough to act on it unattended. This migration keeps the match but demotes
-- it from an auto-approval to a hint: the account still lands PENDING like
-- every other ALUMNI/BUSINESS signup, but the admin notification says which
-- student record it appears to match, so a reviewer can approve it in one
-- look instead of investigating cold.
--
-- Only the ALUMNI branch and the notification body change from 0020;
-- everything else (domain/student-number checks, campus/enrollment_year,
-- company fields) is identical.
--
-- Run after 0020_restore_alumni_auto_verify.sql.
-- ============================================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  meta                    JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::JSONB);
  want_role               user_role;
  new_status              account_status;
  clean_email             TEXT := LOWER(TRIM(NEW.email));
  local_part              TEXT;
  display                 TEXT;
  claimed_student_number  TEXT;
  claimed_faculty         faculty_type;
  alumni_match_id         UUID;
  notif_body              TEXT;
BEGIN
  want_role := COALESCE(NULLIF(meta->>'role', ''), 'STUDENT')::user_role;

  -- Nobody self-registers as an admin.
  IF want_role = 'ADMIN' THEN
    RAISE EXCEPTION 'Admin accounts cannot be self-registered';
  END IF;

  -- Richfield or AAA domain + 9-digit student number enforcement.
  IF want_role = 'STUDENT' THEN
    IF clean_email NOT LIKE '%@my.richfield.ac.za'
       AND clean_email NOT LIKE '%@richfield.ac.za'
       AND clean_email NOT LIKE '%@my.aaa.ac.za'
       AND clean_email NOT LIKE '%@aaa.ac.za' THEN
      RAISE EXCEPTION 'Student registration requires a @richfield.ac.za or @aaa.ac.za email address';
    END IF;
    local_part := SPLIT_PART(clean_email, '@', 1);
    IF local_part !~ '^[0-9]{9}$' THEN
      RAISE EXCEPTION 'Student email prefix must be exactly 9 digits';
    END IF;
  END IF;

  -- Students are trusted by their domain; everyone else — ALUMNI included —
  -- always waits for an admin now. A claimed student-number match no longer
  -- flips this to ACTIVE on its own; see below.
  new_status := CASE WHEN want_role = 'STUDENT' THEN 'ACTIVE' ELSE 'PENDING' END;
  display    := COALESCE(NULLIF(TRIM(meta->>'full_name'), ''), SPLIT_PART(clean_email, '@', 1));

  IF want_role = 'ALUMNI' THEN
    claimed_student_number := NULLIF(TRIM(meta->>'student_number'), '');
    claimed_faculty := NULLIF(meta->>'faculty', '')::faculty_type;

    IF claimed_student_number IS NOT NULL AND claimed_faculty IS NOT NULL THEN
      SELECT p.id INTO alumni_match_id
      FROM profiles p
      WHERE p.role = 'STUDENT'
        AND p.student_number = claimed_student_number
        AND p.faculty = claimed_faculty
      LIMIT 1;
    END IF;
  END IF;

  INSERT INTO profiles (
    id, email, full_name, role, status,
    faculty, course, academic_year, graduation_year, campus, enrollment_year,
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
    NULLIF(meta->>'campus', ''),
    NULLIF(meta->>'enrollment_year', '')::INT,
    NULLIF(meta->>'company_name', ''),
    NULLIF(meta->>'industry', ''),
    CASE WHEN want_role = 'STUDENT' THEN SPLIT_PART(clean_email, '@', 1)
         ELSE NULLIF(meta->>'student_number', '') END,
    NULLIF(meta->>'verification_photo_url', '')
  );

  INSERT INTO onboarding_progress (user_id) VALUES (NEW.id);

  -- Queue the account for admin review. ALUMNI with a plausible student match
  -- gets a distinct message so the reviewer can approve on sight rather than
  -- investigating cold — the match is a hint for a human, not a bypass.
  IF new_status = 'PENDING' THEN
    notif_body := CASE
      WHEN alumni_match_id IS NOT NULL THEN
        display || ' registered as ALUMNI, claiming student number ' ||
        claimed_student_number || ' (' || claimed_faculty ||
        ') — matches an existing student record. Verify before approving.'
      ELSE
        display || ' registered as ' || want_role || ' and needs review.'
    END;

    INSERT INTO notifications (user_id, type, title, body, data)
    SELECT p.id, 'ACCOUNT_APPROVED',
           'New account pending approval',
           notif_body,
           JSONB_BUILD_OBJECT(
             'pending_user_id', NEW.id,
             'alumni_match_profile_id', alumni_match_id
           )
    FROM profiles p WHERE p.role = 'ADMIN';
  END IF;

  RETURN NEW;
END;
$fn$;
