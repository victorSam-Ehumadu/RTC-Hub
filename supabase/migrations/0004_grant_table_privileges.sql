-- ============================================================
-- RTC Hub — 0004: grant base table privileges to authenticated
--
-- RLS decides *which rows* a query can touch, but Postgres still requires
-- an ordinary GRANT before it lets a role attempt the query at all — the
-- two are independent layers. 0001/0002 enabled RLS and wrote policies for
-- every table but never granted SELECT/INSERT/UPDATE/DELETE on any of them
-- to `authenticated`, which is normally set up by Supabase's own project
-- bootstrap and easy to assume is already there. It isn't here, hence
-- "permission denied for table profiles" even after RLS was fixed.
--
-- This grants full CRUD at the table level and leaves RLS as the actual
-- fine-grained boundary, exactly as CLAUDE.md describes: a table with RLS
-- enabled and no policy covering an operation still denies it outright, so
-- e.g. logic_points stays uninsertable by clients (0001 gives it a SELECT
-- policy only) even though this grants INSERT at the table level.
--
-- Run after 0003_fix_profiles_rls_recursion.sql.
-- ============================================================

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

-- So tables added by later migrations (0005+, per-stream) inherit this
-- automatically instead of needing their own GRANT block.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
