-- ============================================================
-- RTC Hub — 0019: self-service account deletion
--
-- Deleting a profiles row directly (what AdminRepository.deleteUser already
-- does) leaves the matching auth.users row orphaned, since the client can't
-- touch the auth schema directly. Self-service deletion needs to go the
-- other way: delete auth.users and let "profiles.id REFERENCES
-- auth.users(id) ON DELETE CASCADE" (0001) take care of profiles and
-- everything under it.
--
-- Two existing profiles(id) foreign keys have no ON DELETE clause and would
-- 23503 the first time someone who was ever admin-actioned or
-- flagged/reported tried to delete their own account:
--   - admin_account_actions.actor_id / target_id (0014)
--   - content_flags.reporter_id / user_id / resolved_by (0001)
-- Fixed here rather than in a separate migration since delete_own_account()
-- is unusable without them. Every FK in this schema uses Postgres's default
-- <table>_<column>_fkey naming (no explicit CONSTRAINT name is given
-- anywhere else in these migrations), so that's what's targeted below; if a
-- name doesn't match what the live project actually has, check with
-- \d admin_account_actions / \d content_flags in the SQL editor and adjust.
--
-- Run after 0014_b_admin_account_actions.sql.
-- ============================================================

-- actor_id (the admin who acted) is nulled out rather than cascaded, so the
-- audit log entry survives that admin's own account later being deleted.
-- target_id (the account acted upon) cascades — once that account is gone,
-- a log entry about it has nothing left to refer to.
ALTER TABLE admin_account_actions ALTER COLUMN actor_id DROP NOT NULL;

ALTER TABLE admin_account_actions
  DROP CONSTRAINT IF EXISTS admin_account_actions_actor_id_fkey,
  ADD CONSTRAINT admin_account_actions_actor_id_fkey
    FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE admin_account_actions
  DROP CONSTRAINT IF EXISTS admin_account_actions_target_id_fkey,
  ADD CONSTRAINT admin_account_actions_target_id_fkey
    FOREIGN KEY (target_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- Same reasoning: reporter_id/user_id (who filed it / who it's about)
-- cascade; resolved_by (the admin who closed it) is nulled out instead so
-- the flag's resolution history survives that admin's account being
-- deleted later.
ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_reporter_id_fkey,
  ADD CONSTRAINT content_flags_reporter_id_fkey
    FOREIGN KEY (reporter_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_user_id_fkey,
  ADD CONSTRAINT content_flags_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE content_flags
  DROP CONSTRAINT IF EXISTS content_flags_resolved_by_fkey,
  ADD CONSTRAINT content_flags_resolved_by_fkey
    FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE SET NULL;

-- A function created via the SQL editor is owned by `postgres`, which has
-- privileges over the auth schema — the same trust boundary
-- admin_reset_password (0014) already relies on. This lets an
-- authenticated user delete their own auth.users row despite holding only
-- an anon-derived JWT. Supabase's auth schema cascades auth.sessions /
-- auth.refresh_tokens on its own, so this only needs the one DELETE.
CREATE OR REPLACE FUNCTION delete_own_account()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$fn$;

GRANT EXECUTE ON FUNCTION delete_own_account() TO authenticated;
