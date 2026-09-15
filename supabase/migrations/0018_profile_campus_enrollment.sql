-- ============================================================
-- RTC Hub — 0018: campus and enrollment year on student/alumni profiles
--
-- The hackathon guidelines (§2.3) mandate "Campus attended" and "Year of
-- enrolment and graduation" on every student/alumni profile. Neither campus
-- nor an enrollment-year column existed at all; graduation_year (0001) did
-- exist but was never surfaced in any UI.
--
-- Extends handle_new_user() again (on top of 0017, not 0002 — keep this the
-- one place the function is defined going forward) to read the two new
-- fields out of raw_user_meta_data the same way graduation_year already is.
--
-- Run after 0017_student_email_domains.sql.
-- ============================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS campus TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS enrollment_year INT;

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

  -- Students are trusted by their domain; everyone else waits for an admin.
  new_status := CASE WHEN want_role = 'STUDENT' THEN 'ACTIVE' ELSE 'PENDING' END;
  display    := COALESCE(NULLIF(TRIM(meta->>'full_name'), ''), SPLIT_PART(clean_email, '@', 1));

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
