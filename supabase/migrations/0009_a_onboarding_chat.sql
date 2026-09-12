-- ============================================================
-- RTC Hub — 0009 (Stream A): AI assistant chat history
--
-- onboarding_progress (tutorial_complete, profile_step) already exists,
-- from 0001, with its own RLS policies (0002: onboarding_select_own /
-- onboarding_update_own) — there is nothing to add there. This migration
-- is the one piece Stream A is actually missing: somewhere to store the
-- assistant conversation itself, so a user's chat with the AI survives
-- closing the app.
--
-- Numbering: 0005 is reserved for Stream C, 0006-0008 went to Stream B
-- (see 0006's header) — so Stream A's first migration is 0009, per
-- WORKPLAN's own fallback rule (number + stream letter) rather than the
-- 0003 the original plan assumed.
-- ============================================================

CREATE TABLE IF NOT EXISTS chat_messages (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  role       TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content    TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- A user's own conversation with the assistant is theirs alone to read and
-- add to — nobody else, including other students, should see it. No
-- UPDATE/DELETE policy: history is append-only, the same spirit as
-- logic_points being read-only to clients (nothing here is worth a client
-- lying about — it's only ever their own chat log — so a plain
-- insert-your-own-rows policy is enough; no trigger or RPC needed).
CREATE POLICY "chat_select_own" ON chat_messages FOR SELECT USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "chat_insert_own" ON chat_messages FOR INSERT WITH CHECK (user_id = auth.uid());

-- Every read the app does is "this user's history, in order" — index for it.
CREATE INDEX IF NOT EXISTS idx_chat_messages_user_created ON chat_messages (user_id, created_at);
