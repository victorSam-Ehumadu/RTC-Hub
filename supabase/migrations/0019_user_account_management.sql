-- ============================================================
-- RTC Hub — 0019: User account management — change password and
-- delete account (self-service). Users can update their own password
-- and delete their own account along with all associated data.
-- ============================================================

-- ─── CHANGE PASSWORD ───────────────────────────────────────────
-- Users can change their own password. Requires the old password
-- for verification, and enforces minimum length.
CREATE OR REPLACE FUNCTION user_change_password(p_old_password TEXT, p_new_password TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  current_user_id UUID;
  stored_hash TEXT;
BEGIN
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Validate new password length
  IF length(p_new_password) < 8 THEN
    RAISE EXCEPTION 'Password must be at least 8 characters';
  END IF;

  -- Verify old password by retrieving the stored hash and comparing
  SELECT encrypted_password INTO stored_hash FROM auth.users WHERE id = current_user_id;

  IF stored_hash IS NULL THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  -- Compare old password with stored hash
  IF NOT (extensions.crypt(p_old_password, stored_hash) = stored_hash) THEN
    RAISE EXCEPTION 'Invalid current password';
  END IF;

  -- Update password
  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
      updated_at = now()
  WHERE id = current_user_id;

  -- Revoke existing sessions/tokens so old password stops working immediately
  DELETE FROM auth.sessions WHERE user_id = current_user_id;
  DELETE FROM auth.refresh_tokens WHERE user_id = current_user_id;
END;
$fn$;

GRANT EXECUTE ON FUNCTION user_change_password(TEXT, TEXT) TO authenticated;

-- ─── DELETE ACCOUNT ───────────────────────────────────────────
-- Users can delete their own account. This requires the password for
-- verification and cascades to related data (posts, connections, messages, etc.)
--
-- This function deletes:
-- - All posts and associated comments
-- - All connections (both directions)
-- - All messages in threads
-- - All skills, recommendations, endorsements
-- - The profile itself
-- - Finally, the auth user
CREATE OR REPLACE FUNCTION user_delete_account(p_password TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  current_user_id UUID;
  stored_hash TEXT;
BEGIN
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Verify password
  SELECT encrypted_password INTO stored_hash FROM auth.users WHERE id = current_user_id;

  IF stored_hash IS NULL THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  IF NOT (extensions.crypt(p_password, stored_hash) = stored_hash) THEN
    RAISE EXCEPTION 'Invalid password';
  END IF;

  -- Delete in cascade order to avoid FK constraint violations
  -- Start with dependent data before the core tables

  -- Delete comments on their posts
  DELETE FROM comments WHERE post_id IN (SELECT id FROM posts WHERE author_id = current_user_id);

  -- Delete their posts
  DELETE FROM posts WHERE author_id = current_user_id;

  -- Delete their skill endorsements
  DELETE FROM skill_endorsements WHERE endorser_id = current_user_id OR skill_id IN (SELECT id FROM skills WHERE owner_id = current_user_id);

  -- Delete their skills
  DELETE FROM skills WHERE owner_id = current_user_id;

  -- Delete their recommendations
  DELETE FROM recommendations WHERE author_id = current_user_id OR recipient_id = current_user_id;

  -- Delete their messages (both sent and received)
  DELETE FROM messages WHERE sender_id = current_user_id OR recipient_id = current_user_id;

  -- Delete their threads
  DELETE FROM threads WHERE participant_one_id = current_user_id OR participant_two_id = current_user_id;

  -- Delete their connections (both directions)
  DELETE FROM connections WHERE user_one_id = current_user_id OR user_two_id = current_user_id;

  -- Delete their profile
  DELETE FROM profiles WHERE id = current_user_id;

  -- Delete the auth user (this cascades to auth.sessions and auth.refresh_tokens)
  DELETE FROM auth.users WHERE id = current_user_id;
END;
$fn$;

GRANT EXECUTE ON FUNCTION user_delete_account(TEXT) TO authenticated;