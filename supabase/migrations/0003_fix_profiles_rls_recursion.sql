-- ============================================================
-- RTC Hub — 0003: fix infinite recursion in profiles RLS
--
-- Any query that evaluated is_admin() — which is every policy in 0002 that
-- says "OR is_admin()" — recursed: is_admin() is a plain LANGUAGE sql
-- function, not SECURITY DEFINER, so its own `SELECT ... FROM profiles`
-- runs as the calling user and is itself subject to profiles' RLS. That
-- re-enters the profiles_select policy, which calls is_admin() again, and
-- so on until Postgres gives up with 42P17 "infinite recursion detected in
-- policy for relation profiles". The profiles_select policy added in 0002
-- had a second copy of the same bug: an inline
-- `(SELECT role FROM profiles me WHERE me.id = auth.uid())` subquery,
-- querying profiles from inside a policy defined on profiles.
--
-- Fix: both role checks move into SECURITY DEFINER helper functions. A
-- SECURITY DEFINER function runs as its owner (the table owner in Supabase),
-- and table owners bypass RLS by default — so the internal lookup no longer
-- re-triggers the policy it's being called from. This is the same pattern
-- already used by handle_new_user() and profiles_before_update() in 0002;
-- is_admin() should have been defined this way from the start.
--
-- Run after 0002_client_direct_access.sql.
-- ============================================================

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN');
$$;

-- Replaces the inline self-join in profiles_select — same recursion risk,
-- same fix.
CREATE OR REPLACE FUNCTION my_role()
RETURNS user_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$;

DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (
  id = auth.uid()
  OR is_admin()
  OR (
    status = 'ACTIVE' AND (
      CASE
        WHEN my_role() = 'BUSINESS' THEN visibility_business
        ELSE visibility_peers
      END
    )
  )
);
