-- ============================================================
-- RTC Hub — 0009: finish the notification coverage
--
-- 0002 wired triggers for reactions, comments, messages, connections,
-- endorsements, account status and opportunity activation. 0008 added
-- submissions and replies. What was left is the set of events where
-- something happens *to* a user and the app simply never told them:
--
--   * a student applies to your listing and you find out by opening the
--     applications tab on the off-chance;
--   * a business shortlists or rejects you and you never hear;
--   * someone in your circle posts a bounty worth points and it scrolls past;
--   * an admin schedules an event for your faculty;
--   * a bounty you submitted an answer to closes without you.
--
-- Volume is the thing to be careful with. A notification for every post by
-- every connection is what makes people turn notifications off, so the post
-- trigger below deliberately fires for bounties only — there are points on
-- the table and a person waiting, which is worth an interruption. Ordinary
-- posts stay in the feed where they belong.
--
-- Run after 0008_submissions_and_sheets.sql.
-- ============================================================


-- ─── APPLICATIONS ────────────────────────────────────────────
-- The business owns the listing but has no way to know an application
-- arrived, which for a recruiting employer is the single most important
-- event in the product.

CREATE OR REPLACE FUNCTION on_application_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  owner_id UUID;
  listing  TEXT;
  actor    TEXT;
BEGIN
  SELECT business_id, title INTO owner_id, listing
    FROM opportunities WHERE id = NEW.opportunity_id;
  IF owner_id IS NULL OR owner_id = NEW.applicant_id THEN RETURN NEW; END IF;

  SELECT full_name INTO actor FROM profiles WHERE id = NEW.applicant_id;

  PERFORM notify(owner_id, 'OPPORTUNITY_MATCH',
                 'New application: ' || listing,
                 actor || ' applied.',
                 JSONB_BUILD_OBJECT('opportunity_id', NEW.opportunity_id,
                                    'application_id', NEW.id,
                                    'applicant_id', NEW.applicant_id));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_application_notify ON opportunity_applications;
CREATE TRIGGER trg_application_notify
  AFTER INSERT ON opportunity_applications
  FOR EACH ROW EXECUTE FUNCTION on_application_created();


-- The other direction. Being shortlisted is good news nobody was delivering,
-- and being rejected is worth knowing so people stop waiting.
CREATE OR REPLACE FUNCTION on_application_status_changed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  listing TEXT;
  company TEXT;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;

  SELECT o.title, COALESCE(p.company_name, p.full_name)
    INTO listing, company
    FROM opportunities o
    JOIN profiles p ON p.id = o.business_id
   WHERE o.id = NEW.opportunity_id;

  PERFORM notify(
    NEW.applicant_id,
    'OPPORTUNITY_MATCH',
    CASE NEW.status
      WHEN 'SHORTLISTED' THEN 'Shortlisted for ' || listing
      WHEN 'REJECTED'    THEN 'Update on ' || listing
      ELSE 'Your application changed'
    END,
    CASE NEW.status
      WHEN 'SHORTLISTED' THEN company || ' shortlisted you. Expect to hear from them.'
      WHEN 'REJECTED'    THEN company || ' is not taking this one further.'
      ELSE company || ' set your application to ' || LOWER(NEW.status) || '.'
    END,
    JSONB_BUILD_OBJECT('opportunity_id', NEW.opportunity_id,
                       'application_id', NEW.id,
                       'status', NEW.status));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_application_status_notify ON opportunity_applications;
CREATE TRIGGER trg_application_status_notify
  AFTER UPDATE ON opportunity_applications
  FOR EACH ROW EXECUTE FUNCTION on_application_status_changed();


-- ─── BOUNTIES FROM YOUR CIRCLE ───────────────────────────────
-- Bounties only, and connections only. A notification per post per connection
-- is how an app teaches people to mute it; a bounty is different because
-- there are points on the table and someone is actually stuck.
--
-- Faculty is respected: 0007 made cross-faculty posts unreadable, and
-- notifying someone about a post they cannot open would be worse than
-- silence.

CREATE OR REPLACE FUNCTION on_bounty_posted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE actor TEXT;
BEGIN
  IF NOT NEW.is_bounty THEN RETURN NEW; END IF;

  SELECT full_name INTO actor FROM profiles WHERE id = NEW.author_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT c.other, 'BOUNTY_SOLVED',
         actor || ' posted a bounty',
         LEFT(NEW.content, 90),
         JSONB_BUILD_OBJECT('post_id', NEW.id, 'author_id', NEW.author_id)
  FROM (
    SELECT CASE WHEN sender_id = NEW.author_id THEN receiver_id ELSE sender_id END AS other
      FROM connections
     WHERE status = 'ACCEPTED'
       AND (sender_id = NEW.author_id OR receiver_id = NEW.author_id)
  ) c
  JOIN profiles p ON p.id = c.other
 WHERE p.status = 'ACTIVE'
   AND (NEW.faculty IS NULL OR NEW.faculty = ANY (p.content_interests));

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_bounty_posted_notify ON posts;
CREATE TRIGGER trg_bounty_posted_notify
  AFTER INSERT ON posts
  FOR EACH ROW EXECUTE FUNCTION on_bounty_posted();


-- ─── LOSING A BOUNTY ─────────────────────────────────────────
-- accept_bounty_solution() already congratulates the winner. Everyone else
-- who submitted an answer was left refreshing a thread that had quietly
-- closed. Telling them costs nothing and is the difference between a
-- community and a leaderboard.

CREATE OR REPLACE FUNCTION on_bounty_closed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE winner UUID;
BEGIN
  IF NOT (NEW.bounty_solved AND OLD.bounty_solved IS DISTINCT FROM TRUE) THEN
    RETURN NEW;
  END IF;

  SELECT author_id INTO winner
    FROM comments
   WHERE post_id = NEW.id AND is_solution
   LIMIT 1;

  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT DISTINCT c.author_id, 'BOUNTY_SOLVED',
         'A bounty you answered was solved',
         'Another answer was accepted. The thread is still worth a read.',
         JSONB_BUILD_OBJECT('post_id', NEW.id)
  FROM comments c
  WHERE c.post_id = NEW.id
    AND c.kind = 'SUBMISSION'
    AND c.author_id IS DISTINCT FROM winner
    AND c.author_id IS DISTINCT FROM NEW.author_id;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_bounty_closed_notify ON posts;
CREATE TRIGGER trg_bounty_closed_notify
  AFTER UPDATE ON posts
  FOR EACH ROW EXECUTE FUNCTION on_bounty_closed();


-- ─── EVENTS ──────────────────────────────────────────────────
-- 0001 created the events table and nothing ever announced one, so an event
-- existed only for whoever happened to open the events screen.

CREATE OR REPLACE FUNCTION on_event_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT p.id, 'ADMIN_ANNOUNCEMENT',
         NEW.title,
         'On ' || TO_CHAR(NEW.event_date, 'Dy DD Mon at HH24:MI')
               || COALESCE(' · ' || NEW.location, ''),
         JSONB_BUILD_OBJECT('event_id', NEW.id)
  FROM profiles p
  WHERE p.status = 'ACTIVE'
    -- Same audience rules the events_select policy applies, so nobody is
    -- told about an event they cannot then open.
    AND (NEW.faculty IS NULL OR NEW.faculty = ANY (p.content_interests))
    AND (NEW.target_roles IS NULL OR p.role = ANY (NEW.target_roles));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_event_notify ON events;
CREATE TRIGGER trg_event_notify
  AFTER INSERT ON events
  FOR EACH ROW EXECUTE FUNCTION on_event_created();


-- ─── READING THEM ────────────────────────────────────────────
-- Opening a chat marks its messages read, but the matching NEW_MESSAGE
-- notifications stayed unread, so the bell kept climbing until someone
-- visited the notifications screen and cleared everything at once. Marking
-- them from the client would mean a policy that lets a user update rows by
-- someone else's sender id, so it happens here instead.

CREATE OR REPLACE FUNCTION mark_thread_notifications_read(p_other UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  UPDATE notifications
     SET read = TRUE
   WHERE user_id = auth.uid()
     AND read = FALSE
     AND type = 'NEW_MESSAGE'
     AND data->>'sender_id' = p_other::TEXT;
END;
$fn$;

GRANT EXECUTE ON FUNCTION mark_thread_notifications_read(UUID) TO authenticated;

-- Same problem on a post: opening the thread should clear the notifications
-- that pointed at it.
CREATE OR REPLACE FUNCTION mark_post_notifications_read(p_post UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  UPDATE notifications
     SET read = TRUE
   WHERE user_id = auth.uid()
     AND read = FALSE
     AND data->>'post_id' = p_post::TEXT;
END;
$fn$;

GRANT EXECUTE ON FUNCTION mark_post_notifications_read(UUID) TO authenticated;


-- ─── COUNTING THEM ───────────────────────────────────────────
-- NotificationRepository.unreadCount() selects every unread row and takes
-- the list length, which PostgREST caps at 1000 — so a busy account would
-- show a badge that quietly stopped counting. Count in the database.

CREATE OR REPLACE FUNCTION unread_notification_count()
RETURNS INT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT COUNT(*)::INT FROM notifications
   WHERE user_id = auth.uid() AND read = FALSE;
$fn$;

GRANT EXECUTE ON FUNCTION unread_notification_count() TO authenticated;


-- ─── HOUSEKEEPING ────────────────────────────────────────────
-- Read notifications older than 60 days are noise nobody will scroll to.
-- Not scheduled here: pg_cron has to be enabled on the project first, and a
-- migration that assumes it fails on a project that has not. Schedule with
--
--   SELECT cron.schedule('prune-notifications', '0 3 * * *',
--                        $$SELECT prune_notifications()$$);
--
-- once the extension is on.

CREATE OR REPLACE FUNCTION prune_notifications()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE removed INT;
BEGIN
  DELETE FROM notifications
   WHERE read = TRUE AND created_at < NOW() - INTERVAL '60 days';
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END;
$fn$;
