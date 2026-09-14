-- ============================================================
-- RTC Hub — 0017: accept all four guideline-mandated student email domains
--
-- handle_new_user() (0002) only accepted @my.richfield.ac.za and
-- @richfield.ac.za. The binding hackathon guidelines (§2.1) mandate four:
-- @my.richfield.ac.za, @richfield.ac.za, @my.aaa.ac.za and @aaa.ac.za —
-- registration from the AAA partner-campus domains was being rejected
-- outright. The client-side copy of this rule (isValidStudentEmail in
-- lib/core/constants.dart) is UX only; this is the real enforcement per
-- CLAUDE.md's security model, so it has to change here too.
--
-- Identical to 0002's handle_new_user() in every other respect — only the
-- domain check is extended from 2 to 4 domains.
--
-- Run after 0002_client_direct_access.sql.
-- ============================================================

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
