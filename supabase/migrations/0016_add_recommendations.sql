-- ============================================================
-- RTC Hub — 0016: add recommendations feature
--
-- Allows users to write peer recommendations that are visible
-- on their profile after recipient approval.
-- ============================================================

-- ─── RECOMMENDATIONS TABLE ─────────────────────────────────
CREATE TABLE recommendations (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipient_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  body            TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'PENDING',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(author_id, recipient_id),
  CHECK (author_id <> recipient_id)
);

-- ─── INDEXES ───────────────────────────────────────────────
CREATE INDEX idx_recommendations_recipient ON recommendations(recipient_id);
CREATE INDEX idx_recommendations_status ON recommendations(status);

-- ─── RLS POLICIES ──────────────────────────────────────────
ALTER TABLE recommendations ENABLE ROW LEVEL SECURITY;

-- Recipient can see all their recommendations (pending + approved)
-- Author can see their own recommendations
-- Public can see only approved recommendations
CREATE POLICY "rec_select" ON recommendations FOR SELECT USING (
  auth.uid() = recipient_id OR
  auth.uid() = author_id OR
  status = 'APPROVED' OR
  is_admin()
);

-- Only author can insert
CREATE POLICY "rec_insert" ON recommendations FOR INSERT WITH CHECK (
  author_id = auth.uid()
);

-- Only recipient can update (to approve/decline)
CREATE POLICY "rec_update" ON recommendations FOR UPDATE USING (
  recipient_id = auth.uid() OR is_admin()
);

-- Author can delete their own, or admin can delete any
CREATE POLICY "rec_delete" ON recommendations FOR DELETE USING (
  author_id = auth.uid() OR is_admin()
);

-- ─── NOTIFICATIONS: Recommendation triggers ─────────────────

-- Notify recipient when recommendation is submitted
CREATE OR REPLACE FUNCTION trg_recommendation_submitted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  author_name TEXT;
BEGIN
  SELECT full_name INTO author_name FROM profiles WHERE id = NEW.author_id;

  PERFORM notify(
    NEW.recipient_id,
    'RECOMMENDATION_PENDING',
    'New recommendation',
    author_name || ' wrote a recommendation for you.',
    JSONB_BUILD_OBJECT('recommendation_id', NEW.id, 'author_id', NEW.author_id)
  );
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_rec_submitted ON recommendations;
CREATE TRIGGER trg_rec_submitted
  AFTER INSERT ON recommendations
  FOR EACH ROW EXECUTE FUNCTION trg_recommendation_submitted();

-- Notify author when recommendation is approved
CREATE OR REPLACE FUNCTION trg_recommendation_approved()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  recipient_name TEXT;
BEGIN
  IF OLD.status = 'PENDING' AND NEW.status = 'APPROVED' THEN
    SELECT full_name INTO recipient_name FROM profiles WHERE id = NEW.recipient_id;

    PERFORM notify(
      NEW.author_id,
      'RECOMMENDATION_APPROVED',
      'Recommendation approved',
      recipient_name || ' approved your recommendation.',
      JSONB_BUILD_OBJECT('recommendation_id', NEW.id, 'recipient_id', NEW.recipient_id)
    );
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_rec_approved ON recommendations;
CREATE TRIGGER trg_rec_approved
  AFTER UPDATE ON recommendations
  FOR EACH ROW EXECUTE FUNCTION trg_recommendation_approved();
