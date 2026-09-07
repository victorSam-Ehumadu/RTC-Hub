-- ============================================================
-- One-off repair: recreate a profiles row for an auth.users account whose
-- profiles row was deleted directly (bypassing auth.users), so the trigger
-- never re-ran. Not a schema change — don't number/keep this alongside the
-- real migrations; run it once in the SQL editor and discard.
--
-- Mirrors handle_new_user() in 0002_client_direct_access.sql exactly, but
-- reads the fields back out of the surviving auth.users.raw_user_meta_data
-- instead of asking for them again. Also recreates onboarding_progress,
-- which cascades off profiles (not auth.users) and so was deleted with it.
--
-- Fill in the email below, then run this whole file in the Supabase SQL
-- editor. It runs as the table owner there, so it bypasses RLS — the same
-- reason handle_new_user() itself is SECURITY DEFINER.
-- ============================================================

DO $$
DECLARE
  u           auth.users%ROWTYPE;
  meta        JSONB;
  want_role   user_role;
  new_status  account_status;
  clean_email TEXT;
  local_part  TEXT;
  display     TEXT;
BEGIN
  SELECT * INTO u FROM auth.users WHERE email = LOWER(TRIM('PUT_EMAIL_HERE'));
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No auth.users row for that email';
  END IF;

  IF EXISTS (SELECT 1 FROM profiles WHERE id = u.id) THEN
    RAISE EXCEPTION 'profiles row already exists for %, nothing to do', u.email;
  END IF;

  meta        := COALESCE(u.raw_user_meta_data, '{}'::JSONB);
  clean_email := LOWER(TRIM(u.email));
  local_part  := SPLIT_PART(clean_email, '@', 1);
  want_role   := COALESCE(NULLIF(meta->>'role', ''), 'STUDENT')::user_role;
  new_status  := CASE WHEN want_role = 'STUDENT' THEN 'ACTIVE' ELSE 'PENDING' END;
  display     := COALESCE(NULLIF(TRIM(meta->>'full_name'), ''), local_part);

  INSERT INTO profiles (
    id, email, full_name, role, status,
    faculty, course, academic_year, graduation_year,
    company_name, industry, student_number, verification_photo_url
  ) VALUES (
    u.id, clean_email, display, want_role, new_status,
    NULLIF(meta->>'faculty', '')::faculty_type,
    NULLIF(meta->>'course', ''),
    NULLIF(meta->>'academic_year', ''),
    NULLIF(meta->>'graduation_year', '')::INT,
    NULLIF(meta->>'company_name', ''),
    NULLIF(meta->>'industry', ''),
    CASE WHEN want_role = 'STUDENT' THEN local_part
         ELSE NULLIF(meta->>'student_number', '') END,
    NULLIF(meta->>'verification_photo_url', '')
  );

  INSERT INTO onboarding_progress (user_id) VALUES (u.id)
  ON CONFLICT (user_id) DO NOTHING;

  RAISE NOTICE 'Recreated profile % (%) as % / %', display, clean_email, want_role, new_status;
END $$;
