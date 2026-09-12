-- ============================================================
-- RTC Hub — 0009 (Stream B): administrator analytics dashboard (§2.7)
--
-- §2.7 spells out this dashboard's contents in full, unlike the student
-- one: "total registered users by type, monthly active users, new
-- registrations over time, content volume (posts, videos, opportunities),
-- flagged content count, and business user approval pipeline status."
-- Flagged content count is already covered by the existing pending-review
-- tile grid in AdminScreen (an icon + colour + number is itself a visual
-- indicator, not a raw number) so it isn't repeated here — the five
-- functions below cover the rest.
--
-- All five are SECURITY DEFINER, unlike 0007's plain-SQL student RPCs,
-- for two different reasons:
--   - admin_monthly_active_users reads auth.users.last_sign_in_at, which
--     has no PostgREST route and no RLS policy of its own — SECURITY
--     DEFINER is the only way to read it at all.
--   - the rest aggregate across every profile/post/opportunity regardless
--     of the caller's own RLS-visible slice, which a non-admin must never
--     get back (profiles_select alone would silently give a non-admin a
--     skewed count, not an error).
-- Every function re-checks is_admin() itself and raises 'Administrators
-- only' otherwise, the same shape as broadcast_announcement (0002) — a
-- stolen anon key calling these directly gets refused, not a filtered
-- result.
--
-- Run after 0008_b_business_skill_searches.sql.
-- ============================================================

-- ─── TOTAL REGISTERED USERS BY TYPE ───────────────────────────
CREATE OR REPLACE FUNCTION admin_users_by_role()
RETURNS TABLE(role user_role, total BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY
    SELECT p.role, COUNT(*) FROM profiles p GROUP BY p.role ORDER BY p.role;
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_users_by_role() TO authenticated;

-- ─── MONTHLY ACTIVE USERS ──────────────────────────────────────
-- Proxy: accounts with an auth.users.last_sign_in_at inside the last 30
-- days. There is no in-app "last active" ping today, and auth.users
-- already tracks exactly this for every session Supabase Auth issues.
--
-- VERIFY BEFORE DEMOING: this function is only as good as `postgres`
-- (the role that owns it once pasted into the SQL editor) having SELECT on
-- auth.users, which is normal on Supabase but not guaranteed on every
-- project configuration. Test by calling it as a real signed-in admin
-- through the app — a permission error here means falling back to
-- `SELECT COUNT(DISTINCT user_id) FROM profile_analytics WHERE date >=
-- CURRENT_DATE - 30` instead (weaker: engagement received, not sign-ins),
-- and that substitution should be written down here, not made silently.
CREATE OR REPLACE FUNCTION admin_monthly_active_users()
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE mau BIGINT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;
  SELECT COUNT(*) INTO mau
  FROM auth.users u
  WHERE u.last_sign_in_at >= NOW() - INTERVAL '30 days';
  RETURN mau;
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_monthly_active_users() TO authenticated;

-- ─── NEW REGISTRATIONS OVER TIME ──────────────────────────────
-- A zero-filled 30-day series (LEFT JOIN against generate_series) so the
-- line chart doesn't silently skip days with no signups. The series is
-- aliased as gs(d) and grouped/ordered by gs.d explicitly — grouping by a
-- bare generate_series alias risks Postgres treating it as the whole
-- row-type rather than the timestamp column, and the output column is
-- named `day`, distinct from the loop variable, to avoid any ambiguity
-- inside the RETURNS TABLE scope.
CREATE OR REPLACE FUNCTION admin_registrations_by_day(p_days INT DEFAULT 30)
RETURNS TABLE(day DATE, signups BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY
    SELECT gs.d::DATE, COUNT(p.id)
    FROM generate_series(
           CURRENT_DATE - (GREATEST(p_days, 1) - 1),
           CURRENT_DATE,
           INTERVAL '1 day'
         ) AS gs(d)
    LEFT JOIN profiles p ON p.created_at::DATE = gs.d::DATE
    GROUP BY gs.d
    ORDER BY gs.d;
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_registrations_by_day(INT) TO authenticated;

-- ─── CONTENT VOLUME ────────────────────────────────────────────
-- Posts split by type — "videos" in the brief is post_type = 'VIDEO' —
-- plus opportunities as their own row, since they're a different table
-- and kind of content, not another post type.
CREATE OR REPLACE FUNCTION admin_content_volume()
RETURNS TABLE(kind TEXT, total BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY
    SELECT p.type::TEXT, COUNT(*) FROM posts p GROUP BY p.type
    UNION ALL
    SELECT 'OPPORTUNITY', COUNT(*) FROM opportunities;
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_content_volume() TO authenticated;

-- ─── BUSINESS APPROVAL PIPELINE ────────────────────────────────
-- BUSINESS-role profiles grouped by account_status. PENDING is the queue
-- an admin actually needs to clear; ACTIVE/SUSPENDED/REJECTED give the
-- rest of the funnel for context, same status vocabulary as everywhere
-- else in the schema.
CREATE OR REPLACE FUNCTION admin_business_pipeline()
RETURNS TABLE(status account_status, total BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Administrators only'; END IF;
  RETURN QUERY
    SELECT p.status, COUNT(*) FROM profiles p
    WHERE p.role = 'BUSINESS'
    GROUP BY p.status ORDER BY p.status;
END;
$fn$;

GRANT EXECUTE ON FUNCTION admin_business_pipeline() TO authenticated;
