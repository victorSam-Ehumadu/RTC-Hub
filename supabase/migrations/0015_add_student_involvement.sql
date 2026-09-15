-- ============================================================
-- RTC Hub — 0015: add student involvement field
--
-- Adds a student_involvement TEXT column to profiles for tracking
-- club activities, volunteer work, community involvement, and competitions.
-- ============================================================

ALTER TABLE profiles
ADD COLUMN student_involvement TEXT;

COMMENT ON COLUMN profiles.student_involvement IS
  'Club activities, volunteer work, community involvement, and competitions';