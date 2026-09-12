-- ============================================================
-- RTC Hub — 0008: bounty submissions, attachments and spreadsheets
--
-- A bounty thread does two different jobs and was doing both in one list.
-- People ask clarifying questions, react and chat — and people submit
-- answers, which for an IT bounty is a code file and for a Business bounty
-- is a spreadsheet. Mixing them means the actual answers get buried under
-- "same problem here", and the person paying the bounty has to read the
-- whole thread to find the two comments that matter.
--
-- So comments gain a `kind`, and the UI shows Discussion and Submissions as
-- separate sections. A submission carries a file; discussion does not.
--
-- Spreadsheets are stored as data, not just as an uploaded file, so the app
-- can render a preview and regenerate a clean .xlsx on demand. Excel and
-- Sheets both recalculate formulas on open, which is what makes "run this
-- spreadsheet" mean something — the app does not need its own formula
-- engine to do the job.
--
-- Run after 0007_faculty_segregation.sql.
-- ============================================================


-- ─── SPREADSHEET POSTS ───────────────────────────────────────
-- Deliberately not a new post_type enum value. ALTER TYPE ... ADD VALUE has
-- transaction restrictions that make it awkward to run alongside statements
-- that use the new value, and nothing here needs the type: a post with
-- sheet_data renders as a sheet, the same way a post with code_snippet
-- renders as code.

ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS sheet_data JSONB,
  ADD COLUMN IF NOT EXISTS sheet_name TEXT;

COMMENT ON COLUMN posts.sheet_data IS
  'Spreadsheet contents as {"columns":[...],"rows":[[...]]}. Kept as data '
  'rather than only as an uploaded file so the app can preview it and '
  'regenerate a clean .xlsx for download.';


-- ─── COMMENT KIND ────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'comment_kind') THEN
    CREATE TYPE comment_kind AS ENUM ('DISCUSSION', 'SUBMISSION');
  END IF;
END
$$;

ALTER TABLE comments
  ADD COLUMN IF NOT EXISTS kind comment_kind NOT NULL DEFAULT 'DISCUSSION',
  ADD COLUMN IF NOT EXISTS attachment_url  TEXT,
  ADD COLUMN IF NOT EXISTS attachment_name TEXT,
  ADD COLUMN IF NOT EXISTS attachment_size INT,
  ADD COLUMN IF NOT EXISTS attachment_kind TEXT,   -- CODE | SHEET | FILE
  ADD COLUMN IF NOT EXISTS code_language   TEXT,
  ADD COLUMN IF NOT EXISTS code_snippet    TEXT,
  ADD COLUMN IF NOT EXISTS sheet_data      JSONB;

COMMENT ON COLUMN comments.kind IS
  'SUBMISSION is an answer to a bounty and must carry code, a sheet or a '
  'file. DISCUSSION is everything else. Enforced by trg_comments_guard.';

CREATE INDEX IF NOT EXISTS idx_comments_post_kind
  ON comments(post_id, kind, created_at);


-- ─── GUARD ───────────────────────────────────────────────────
-- Extends the 0002 trigger. Two rules matter beyond the existing ones:
--
--   * a SUBMISSION has to actually contain something submittable, or the
--     Submissions tab fills up with empty rows that look like answers;
--   * only bounty posts have submissions at all.
--
-- is_solution and is_flagged stay frozen exactly as 0002 left them —
-- accept_bounty_solution() is still the only thing that may set is_solution,
-- which is what stops a responder awarding themselves the points.

CREATE OR REPLACE FUNCTION comments_before_write()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE is_bounty_post BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.is_solution := FALSE;
    NEW.is_flagged  := FALSE;

    IF NEW.kind = 'SUBMISSION' THEN
      SELECT p.is_bounty INTO is_bounty_post FROM posts p WHERE p.id = NEW.post_id;

      IF NOT COALESCE(is_bounty_post, FALSE) THEN
        RAISE EXCEPTION 'Only bounty posts accept submissions';
      END IF;

      IF COALESCE(TRIM(NEW.code_snippet), '') = ''
         AND NEW.sheet_data IS NULL
         AND COALESCE(TRIM(NEW.attachment_url), '') = '' THEN
        RAISE EXCEPTION 'A submission needs code, a spreadsheet or a file attached';
      END IF;
    END IF;

  ELSIF NOT is_admin() THEN
    NEW.is_solution := OLD.is_solution;
    NEW.is_flagged  := OLD.is_flagged;
    NEW.author_id   := OLD.author_id;
    -- A submission cannot be quietly downgraded to discussion after the fact,
    -- which would hide an answer the bounty author had already seen.
    NEW.kind        := OLD.kind;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_comments_guard ON comments;
CREATE TRIGGER trg_comments_guard
  BEFORE INSERT OR UPDATE ON comments
  FOR EACH ROW EXECUTE FUNCTION comments_before_write();


-- ─── NOTIFY THE BOUNTY AUTHOR ────────────────────────────────
-- 0002's on_comment_created() sends one generic "New comment on your post".
-- A submission on your own bounty is a different event and deserves to read
-- like one — that is the notification the person is actually waiting for.

CREATE OR REPLACE FUNCTION on_comment_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  author UUID;
  actor  TEXT;
  parent_author UUID;
BEGIN
  SELECT author_id INTO author FROM posts WHERE id = NEW.post_id;
  SELECT full_name INTO actor  FROM profiles WHERE id = NEW.author_id;

  IF author IS NOT NULL AND author <> NEW.author_id THEN
    IF NEW.kind = 'SUBMISSION' THEN
      PERFORM notify(author, 'POST_COMMENT', 'New answer to your bounty',
                     actor || ' submitted an answer.',
                     JSONB_BUILD_OBJECT('post_id', NEW.post_id,
                                        'comment_id', NEW.id,
                                        'kind', 'SUBMISSION'));
    ELSE
      PERFORM notify(author, 'POST_COMMENT', 'New comment on your post',
                     actor || ': ' || LEFT(NEW.content, 80),
                     JSONB_BUILD_OBJECT('post_id', NEW.post_id,
                                        'comment_id', NEW.id));
    END IF;
  END IF;

  -- Replies. 0002 told the post author and left the person actually being
  -- replied to to find out by scrolling.
  IF NEW.parent_id IS NOT NULL THEN
    SELECT author_id INTO parent_author FROM comments WHERE id = NEW.parent_id;
    IF parent_author IS NOT NULL
       AND parent_author <> NEW.author_id
       AND parent_author IS DISTINCT FROM author THEN
      PERFORM notify(parent_author, 'POST_COMMENT', 'Reply to your comment',
                     actor || ': ' || LEFT(NEW.content, 80),
                     JSONB_BUILD_OBJECT('post_id', NEW.post_id,
                                        'comment_id', NEW.id));
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;


-- ─── STORAGE ─────────────────────────────────────────────────
-- Submitted files live in their own bucket rather than post-media, because
-- they are not public: a bounty answer should be readable by people in the
-- thread, not by anyone who guesses the URL.
--
-- Private, so reads go through a signed URL. Same `<uid>/<filename>`
-- ownership convention as every other bucket — the policies in 0002 derive
-- ownership from the first path segment.

INSERT INTO storage.buckets (id, name, public)
VALUES ('submissions', 'submissions', FALSE)
ON CONFLICT (id) DO NOTHING;

-- 0002's own_folder_insert lists its buckets explicitly, so the new one has
-- to be added or uploads are rejected.
DROP POLICY IF EXISTS "own_folder_insert" ON storage.objects;
CREATE POLICY "own_folder_insert" ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id IN ('avatars', 'post-media', 'documents', 'verification', 'submissions')
    AND auth.uid()::TEXT = (storage.foldername(name))[1]
  );

-- Anyone who can read the bounty can read what was submitted to it. Narrower
-- than "signed in" and wider than "only the uploader", which is what a thread
-- needs. The post lookup goes through posts_select, so faculty scoping from
-- 0007 applies here too.
DROP POLICY IF EXISTS "submissions_read" ON storage.objects;
CREATE POLICY "submissions_read" ON storage.objects FOR SELECT
  USING (
    bucket_id = 'submissions'
    AND (
      auth.uid()::TEXT = (storage.foldername(name))[1]
      OR is_admin()
      OR EXISTS (
        SELECT 1
          FROM comments c
          JOIN posts p ON p.id = c.post_id
         WHERE c.attachment_url LIKE '%' || name
      )
    )
  );
