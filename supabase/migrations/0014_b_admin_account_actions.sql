-- ============================================================
-- RTC Hub — 0014 (Stream B): admin account actions — confirm a signup
-- email without the inbox link, and reset a password without the
-- reset-email flow. Replaces the manual SQL-editor workaround in
-- docs/Miscellanous Stuff.txt with a gated RPC any admin can use from
-- the app itself.
--
-- Both functions write auth.users directly. That only works because a
-- SECURITY DEFINER function runs as its owner (`postgres`, once pasted
-- into the SQL editor) rather than as the caller's anon-key role — the
-- same privilege admin_monthly_active_users (migration 0009) already
-- relies on to read auth.users.last_sign_in_at. This is the reason
-- these are RPCs and not, say, a service-role key shipped in the app:
-- the app is a Flutter binary anyone can decompile, so the only key it
-- may ever hold is the anon key (see CLAUDE.md's security model).
--
-- VERIFY BEFORE DEMOING, same as 0009's admin_monthly_active_users: the
-- SQL editor can run with different privileges than the role that ends
-- up owning this function. Test by calling it from the app as a real
-- signed-in admin. A 42501 here means the owning role lacks write
-- access to auth and this needs an Edge Function holding the service
-- role key instead — a heavier alternative this project has otherwise
-- avoided (no Supabase CLI / functions setup exists yet).
--
-- Run after 0013_b_business_dashboard.sql.
-- ============================================================

-- Who did what to whose account, and when — never the password itself.
-- No INSERT policy for any client role: rows are only ever written by
-- the SECURITY DEFINER functions below, the same shape as logic_points
-- having no INSERT policy at all.
CREATE TABLE IF NOT EXISTS admin_account_actions (
  id BIGSERIAL PRIMARY KEY,
  actor_id UUID NOT NULL REFERENCES profiles(id),
  target_id UUID NOT NULL REFERENCES profiles(id),
  action TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE admin_account_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_account_actions_select" ON admin_account_actions
  FOR SELECT USING (is_admin());

-- ─── CONFIRM EMAIL WITHOUT THE INBOX LINK ─────────────────────
CREATE OR REPLACE FUNCTION admin_confirm_email(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'No such account';
  END IF;

  -- Only email_confirmed_at — auth.users.confirmed_at is a generated
  -- column on current Supabase and writing it directly errors.
  UPDATE auth.users
  SET email_confirmed_at = now(), updated_at = now()
  WHERE id = p_user_id;

  INSERT INTO admin_account_actions (actor_id, target_id, action)
  VALUES (auth.uid(), p_user_id, 'CONFIRM_EMAIL');
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_confirm_email(UUID) TO authenticated;

-- ─── RESET PASSWORD WITHOUT THE RESET-EMAIL FLOW ──────────────
-- p_new_password never lands in a table or a log — only
-- extensions.crypt's bcrypt output does, exactly as the SQL-editor
-- snippet in docs/Miscellanous Stuff.txt already did by hand.
--
-- Two guards the SQL-editor version had no reason to have: a minimum
-- length (writing a hash directly bypasses whatever password policy
-- Supabase Auth would otherwise enforce), and a refusal to target
-- another administrator's account (otherwise any admin can seize any
-- other admin's account outright, which the rest of this schema never
-- allows — trg_profiles_guard lets an admin change another admin's
-- profile fields, but a login credential is a different kind of thing).
--
-- Existing sessions/refresh tokens for the account are revoked so the
-- old password stops working immediately rather than staying valid
-- until whatever token TTL was already issued expires.
CREATE OR REPLACE FUNCTION admin_reset_password(p_user_id UUID, p_new_password TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE target_role user_role;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;
  IF length(p_new_password) < 8 THEN
    RAISE EXCEPTION 'Password must be at least 8 characters';
  END IF;

  SELECT role INTO target_role FROM profiles WHERE id = p_user_id;
  IF target_role IS NULL THEN RAISE EXCEPTION 'No such account'; END IF;
  IF target_role = 'ADMIN' AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Cannot reset another administrator''s password';
  END IF;

  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
      updated_at = now()
  WHERE id = p_user_id;

  DELETE FROM auth.sessions WHERE user_id = p_user_id;
  DELETE FROM auth.refresh_tokens WHERE user_id = p_user_id;

  INSERT INTO admin_account_actions (actor_id, target_id, action)
  VALUES (auth.uid(), p_user_id, 'RESET_PASSWORD');
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_reset_password(UUID, TEXT) TO authenticated;
