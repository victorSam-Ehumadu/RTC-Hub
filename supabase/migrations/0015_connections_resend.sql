-- ============================================================
-- RTC Hub — 0015: let a declined connection request be resent
--
-- Today, once a receiver declines a connection request (status ->
-- 'DECLINED'), the sender has no way back in:
--   - conn_update (0001) only lets the RECEIVER update a row, so the sender
--     can't flip their own DECLINED row back to PENDING.
--   - UNIQUE(sender_id, receiver_id) (0001) blocks a fresh INSERT for the
--     same pair while the DECLINED row still occupies it, and there is no
--     DELETE policy to clear it out of the way either.
-- The client-side fix (rendering "Connect" again instead of a permanent
-- "Request pending") needs a way to actually re-send, which needs this
-- policy plus a resend branch in on_connection_change() so the receiver
-- gets a fresh notification instead of the request silently going PENDING
-- with no signal.
--
-- Run after 0002_client_direct_access.sql.
-- ============================================================

-- The sender may move their own DECLINED row back to PENDING — nothing else.
CREATE POLICY "conn_resend" ON connections FOR UPDATE
  USING (sender_id = auth.uid() AND status = 'DECLINED')
  WITH CHECK (status = 'PENDING' AND sender_id = auth.uid());

-- Reuse CONNECTION_REQUEST rather than adding a notif_type enum value for
-- a resend — to the receiver it reads identically to a fresh request, and
-- ALTER TYPE ... ADD VALUE can't safely run in the same transaction as code
-- that references the new value.
CREATE OR REPLACE FUNCTION on_connection_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE actor TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT full_name INTO actor FROM profiles WHERE id = NEW.sender_id;
    PERFORM notify(NEW.receiver_id, 'CONNECTION_REQUEST', 'New connection request',
                   actor || ' wants to connect with you.',
                   JSONB_BUILD_OBJECT('connection_id', NEW.id, 'sender_id', NEW.sender_id));
  ELSIF NEW.status = 'ACCEPTED' AND OLD.status IS DISTINCT FROM 'ACCEPTED' THEN
    SELECT full_name INTO actor FROM profiles WHERE id = NEW.receiver_id;
    PERFORM notify(NEW.sender_id, 'CONNECTION_ACCEPTED', 'Connection accepted',
                   actor || ' accepted your connection request.',
                   JSONB_BUILD_OBJECT('connection_id', NEW.id, 'user_id', NEW.receiver_id));
  ELSIF NEW.status = 'PENDING' AND OLD.status = 'DECLINED' THEN
    SELECT full_name INTO actor FROM profiles WHERE id = NEW.sender_id;
    PERFORM notify(NEW.receiver_id, 'CONNECTION_REQUEST', 'New connection request',
                   actor || ' wants to connect with you.',
                   JSONB_BUILD_OBJECT('connection_id', NEW.id, 'sender_id', NEW.sender_id));
  END IF;
  RETURN NEW;
END;
$fn$;
