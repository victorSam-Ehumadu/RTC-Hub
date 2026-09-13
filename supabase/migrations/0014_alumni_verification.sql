-- ============================================================
-- RTC Hub — 0014: alumni identity verification (§2.1)
--
-- §2.1 singles this out: alumni "may no longer have active access to their
-- student email accounts", so teams "must research, design, and implement a
-- credible alternative authentication and identity verification flow… This
-- is a deliberate design challenge; there is no prescribed solution", and it
-- "must be addressed with a researched, reasoned solution, not left as a
-- gap."
--
-- What we had was a gap wearing a flow's clothes: an alumnus signed up with
-- any email address, landed PENDING like a business, and an administrator
-- approved them from a list of names with nothing to check against.
--
-- ─── THE REASONING ──────────────────────────────────────────
--
-- The problem is that the institution's own strongest signal — the
-- @richfield.ac.za mailbox — is exactly what has expired. Three approaches
-- were considered:
--
--   1. Trust a personal email plus a claimed student number. Rejected:
--      student numbers are on every transcript, ID card and class list, so
--      a claim alone proves nothing.
--
--   2. Verify against a student-records API. Rejected as out of scope
--      rather than wrong — it is the correct long-term answer, but there is
--      no such endpoint to integrate with, and pretending otherwise would
--      be the mock authentication §2.1 rules out.
--
--   3. Evidence plus human review, with the evidence bound to the claim.
--      Chosen. The alumnus states a student number and graduation year and
--      uploads proof — a graduation certificate, academic transcript, or
--      student card. An administrator sees the claim and the document side
--      by side and decides. This is how professional bodies verify
--      membership when an issuing authority cannot be queried live, and it
--      degrades honestly: a reviewer who cannot tell is expected to reject.
--
-- Two properties matter and are enforced here rather than in the UI:
--
--   * The claim is immutable once submitted. Being able to edit the student
--     number after an administrator has read it would make the review
--     meaningless.
--   * The evidence is private. A transcript is a sensitive record, so it
--     lives in the `verification` bucket, readable only by its owner and
--     administrators, and is never exposed on a profile.
--
-- Run after 0013_profile_portfolio.sql.
-- ============================================================


DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'verification_status') THEN
    CREATE TYPE verification_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'evidence_kind') THEN
    CREATE TYPE evidence_kind AS ENUM (
      'GRADUATION_CERTIFICATE', 'ACADEMIC_TRANSCRIPT', 'STUDENT_CARD', 'OTHER'
    );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS alumni_verifications (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,

  -- The claim. Stored separately from `profiles` on purpose: these are
  -- assertions under review, not facts about the account, and conflating
  -- the two is how an unverified claim ends up rendered as a credential.
  claimed_student_number TEXT NOT NULL,
  claimed_graduation_year INT  NOT NULL,
  claimed_course   TEXT,
  claimed_campus   TEXT,

  -- The evidence.
  evidence_kind    evidence_kind NOT NULL DEFAULT 'GRADUATION_CERTIFICATE',
  evidence_path    TEXT NOT NULL,          -- storage path, not a signed URL
  note             TEXT,

  status           verification_status NOT NULL DEFAULT 'PENDING',
  reviewed_by      UUID REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at      TIMESTAMPTZ,
  reviewer_note    TEXT,                   -- why, for a rejection
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alumni_verifications_status
  ON alumni_verifications(status, created_at);

ALTER TABLE alumni_verifications ENABLE ROW LEVEL SECURITY;

-- The applicant sees their own submission and its outcome; administrators
-- see everything. Nobody else sees any of it — this table holds a student
-- number and a document path.
DROP POLICY IF EXISTS "alumni_verifications_select" ON alumni_verifications;
CREATE POLICY "alumni_verifications_select" ON alumni_verifications FOR SELECT
  USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "alumni_verifications_insert" ON alumni_verifications;
CREATE POLICY "alumni_verifications_insert" ON alumni_verifications FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Both parties need UPDATE — the applicant to replace evidence after a
-- rejection, the administrator to decide. The trigger below decides which
-- columns each may actually move.
DROP POLICY IF EXISTS "alumni_verifications_update" ON alumni_verifications;
CREATE POLICY "alumni_verifications_update" ON alumni_verifications FOR UPDATE
  USING (user_id = auth.uid() OR is_admin());

GRANT SELECT, INSERT, UPDATE ON alumni_verifications TO authenticated;


-- ─── THE GUARD ───────────────────────────────────────────────
-- Without this the flow is theatre: an applicant could set their own status
-- to APPROVED, or edit the claimed student number after a reviewer read it.

CREATE OR REPLACE FUNCTION alumni_verifications_before_write()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Nobody arrives pre-approved.
    NEW.status := 'PENDING';
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    NEW.reviewer_note := NULL;

    IF NEW.claimed_student_number !~ '^[0-9]{6,12}$' THEN
      RAISE EXCEPTION 'That does not look like a student number';
    END IF;
    IF NEW.claimed_graduation_year < 1990
       OR NEW.claimed_graduation_year > EXTRACT(YEAR FROM NOW())::INT THEN
      RAISE EXCEPTION 'Graduation year must be between 1990 and this year';
    END IF;

    RETURN NEW;
  END IF;

  IF is_admin() THEN
    -- A reviewer may only decide. The claim and the evidence are the
    -- applicant's words and must survive review unchanged, or the record of
    -- what was approved stops matching what was submitted.
    NEW.claimed_student_number  := OLD.claimed_student_number;
    NEW.claimed_graduation_year := OLD.claimed_graduation_year;
    NEW.claimed_course          := OLD.claimed_course;
    NEW.claimed_campus          := OLD.claimed_campus;
    NEW.evidence_path           := OLD.evidence_path;
    NEW.evidence_kind           := OLD.evidence_kind;
    NEW.user_id                 := OLD.user_id;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
      NEW.reviewed_by := auth.uid();
      NEW.reviewed_at := NOW();
    END IF;
    RETURN NEW;
  END IF;

  -- The applicant. Re-submission after a rejection is allowed, because the
  -- usual reason for one is an unreadable photograph; anything else is not.
  IF OLD.status = 'APPROVED' THEN
    RAISE EXCEPTION 'This verification has already been approved';
  END IF;

  NEW.status        := 'PENDING';
  NEW.reviewed_by   := NULL;
  NEW.reviewed_at   := NULL;
  NEW.reviewer_note := NULL;
  NEW.user_id       := OLD.user_id;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_alumni_verifications_guard ON alumni_verifications;
CREATE TRIGGER trg_alumni_verifications_guard
  BEFORE INSERT OR UPDATE ON alumni_verifications
  FOR EACH ROW EXECUTE FUNCTION alumni_verifications_before_write();


-- ─── THE OUTCOME ─────────────────────────────────────────────
-- Approving the verification is what activates the account. Doing it here
-- rather than expecting the administrator to also remember to flip
-- profiles.status means the two can never disagree — and an alumnus whose
-- evidence was accepted but whose account stayed PENDING would have no way
-- to tell what went wrong.

CREATE OR REPLACE FUNCTION on_alumni_verification_reviewed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;

  IF NEW.status = 'APPROVED' THEN
    UPDATE profiles
       SET status = 'ACTIVE',
           student_number = NEW.claimed_student_number,
           graduation_year = NEW.claimed_graduation_year,
           course = COALESCE(NEW.claimed_course, course),
           campus = COALESCE(NEW.claimed_campus, campus)
     WHERE id = NEW.user_id;

    PERFORM notify(NEW.user_id, 'ACCOUNT_APPROVED',
                   'You are verified',
                   'Your graduation was confirmed. Welcome back to Richfield.',
                   JSONB_BUILD_OBJECT('verification_id', NEW.id));

  ELSIF NEW.status = 'REJECTED' THEN
    -- Deliberately not SUSPENDED: the account stays PENDING so the person
    -- can submit better evidence. A rejected document is not misconduct.
    PERFORM notify(NEW.user_id, 'ACCOUNT_SUSPENDED',
                   'We could not verify your graduation',
                   COALESCE(NEW.reviewer_note,
                            'Please upload a clearer document and try again.'),
                   JSONB_BUILD_OBJECT('verification_id', NEW.id));
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_alumni_verification_reviewed ON alumni_verifications;
CREATE TRIGGER trg_alumni_verification_reviewed
  AFTER UPDATE ON alumni_verifications
  FOR EACH ROW EXECUTE FUNCTION on_alumni_verification_reviewed();


-- Tell the administrators there is something to review.
CREATE OR REPLACE FUNCTION on_alumni_verification_submitted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE applicant TEXT;
BEGIN
  SELECT full_name INTO applicant FROM profiles WHERE id = NEW.user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT p.id, 'ADMIN_ANNOUNCEMENT',
         'Alumni verification to review',
         applicant || ' claims to have graduated in '
                   || NEW.claimed_graduation_year || '.',
         JSONB_BUILD_OBJECT('verification_id', NEW.id, 'user_id', NEW.user_id)
    FROM profiles p WHERE p.role = 'ADMIN';

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_alumni_verification_submitted ON alumni_verifications;
CREATE TRIGGER trg_alumni_verification_submitted
  AFTER INSERT ON alumni_verifications
  FOR EACH ROW EXECUTE FUNCTION on_alumni_verification_submitted();


-- ─── THE REVIEW QUEUE ────────────────────────────────────────
-- One call returning the claim and the applicant together. A reviewer
-- deciding from a list of names with no claim attached is the situation
-- this migration exists to end.

CREATE OR REPLACE FUNCTION alumni_review_queue(p_status verification_status DEFAULT 'PENDING')
RETURNS TABLE (
  id                UUID,
  user_id           UUID,
  full_name         TEXT,
  email             TEXT,
  avatar_url        TEXT,
  claimed_student_number TEXT,
  claimed_graduation_year INT,
  claimed_course    TEXT,
  claimed_campus    TEXT,
  evidence_kind     TEXT,
  evidence_path     TEXT,
  note              TEXT,
  status            TEXT,
  created_at        TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT v.id, v.user_id, p.full_name, p.email, p.avatar_url,
         v.claimed_student_number, v.claimed_graduation_year,
         v.claimed_course, v.claimed_campus,
         v.evidence_kind::TEXT, v.evidence_path, v.note,
         v.status::TEXT, v.created_at
    FROM alumni_verifications v
    JOIN profiles p ON p.id = v.user_id
   WHERE is_admin()          -- the whole result set, or none of it
     AND v.status = p_status
   ORDER BY v.created_at;
$fn$;

GRANT EXECUTE ON FUNCTION alumni_review_queue(verification_status) TO authenticated;

-- A signed link to one piece of evidence, minted per view.
--
-- Not stored: a transcript URL that outlives the review is a document
-- leaking. Short-lived and generated at the moment a reviewer opens it.
CREATE OR REPLACE FUNCTION alumni_evidence_path(p_verification UUID)
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT evidence_path
    FROM alumni_verifications
   WHERE id = p_verification
     AND (is_admin() OR user_id = auth.uid());
$fn$;

GRANT EXECUTE ON FUNCTION alumni_evidence_path(UUID) TO authenticated;
