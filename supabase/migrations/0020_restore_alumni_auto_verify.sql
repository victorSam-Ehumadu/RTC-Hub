-- ============================================================
-- RTC Hub — 0020: restore alumni auto-verify after a migration collision
--
-- This branch's earlier migrations (now renumbered — see below) rebuilt
-- handle_new_user() from an old base that predated a teammate's alumni
-- auto-verify logic (an alumnus claiming the same student_number + faculty
-- as an existing STUDENT record is auto-approved instead of landing
-- PENDING). If that teammate's migration had already run against this
-- project, pasting this branch's version overwrote it — not destructively
-- (no rows were touched), but any ALUMNI signup since then landed PENDING
-- instead of being auto-verified.
--
-- This is the complete, merged body: the teammate's alumni auto-verify
-- logic + this branch's 4-domain check + campus/enrollment_year handling +
-- the existing student_number/verification_photo_url handling. Safe to run
-- regardless of exactly which version was live before — CREATE OR REPLACE
-- makes this the definitive version either way.
--
-- Run this now, immediately, on the live project.
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
  alumni_auto_verified    BOOLEAN := FALSE;
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

  -- Students are trusted by their domain; everyone else waits for an admin
  -- unless the alumni auto-match below says otherwise.
  new_status := CASE WHEN want_role = 'STUDENT' THEN 'ACTIVE' ELSE 'PENDING' END;
  display    := COALESCE(NULLIF(TRIM(meta->>'full_name'), ''), SPLIT_PART(clean_email, '@', 1));

  IF want_role = 'ALUMNI' THEN
    claimed_student_number := NULLIF(TRIM(meta->>'student_number'), '');
    claimed_faculty := NULLIF(meta->>'faculty', '')::faculty_type;

    IF claimed_student_number IS NOT NULL AND claimed_faculty IS NOT NULL THEN
      SELECT TRUE INTO alumni_auto_verified
      FROM profiles p
      WHERE p.role = 'STUDENT'
        AND p.student_number = claimed_student_number
        AND p.faculty = claimed_faculty
      LIMIT 1;
    END IF;

    IF alumni_auto_verified THEN
      new_status := 'ACTIVE';
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
