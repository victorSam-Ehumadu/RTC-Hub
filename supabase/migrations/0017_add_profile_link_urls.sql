-- ============================================================
-- RTC Hub — 0017: add LinkedIn and Credly URLs to profiles
-- ============================================================

ALTER TABLE profiles
ADD COLUMN linkedin_url TEXT,
ADD COLUMN credly_url TEXT;

CREATE INDEX idx_profiles_linkedin ON profiles(linkedin_url);
CREATE INDEX idx_profiles_credly ON profiles(credly_url);
