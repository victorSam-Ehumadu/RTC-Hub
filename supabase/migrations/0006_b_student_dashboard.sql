-- ============================================================
-- RTC Hub — 0006 (Stream B): student dashboard analytics, part 1
--
-- profile_analytics has carried post_reactions and new_connections columns
-- since 0001, but nothing has ever written to them — only profile_views is
-- populated, via record_profile_view() in 0002. These two triggers close
-- that gap using the same SECURITY DEFINER upsert pattern, so
-- AnalyticsRepository.forStudent() (lib/data/admin_repository.dart) has
-- real daily series to chart instead of dead columns.
--
-- Numbering note: 0003/0004 already consumed the numbers WORKPLAN reserved
-- for streams A and B (they turned out to be general fixes, not stream
-- work), and 0005 is still reserved for Stream C's alumni/profile
-- migration. So this stream's first migration is 0006, per WORKPLAN's own
-- fallback rule (number + stream letter) rather than reusing 0004/0005.
-- ============================================================

-- ─── CONNECTION GROWTH ───────────────────────────────────────
-- Fires once per connection, the moment it actually becomes ACCEPTED —
-- same OLD/NEW status check as on_connection_change() in 0002 — and
-- credits both sides, since connections are symmetric per CLAUDE.md
-- (either party may be sender or receiver).
CREATE OR REPLACE FUNCTION profile_analytics_on_connection_accepted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NEW.status = 'ACCEPTED' AND OLD.status IS DISTINCT FROM 'ACCEPTED' THEN
    INSERT INTO profile_analytics (user_id, date, new_connections)
    VALUES (NEW.sender_id, CURRENT_DATE, 1)
    ON CONFLICT (user_id, date)
    DO UPDATE SET new_connections = profile_analytics.new_connections + 1;

    INSERT INTO profile_analytics (user_id, date, new_connections)
    VALUES (NEW.receiver_id, CURRENT_DATE, 1)
    ON CONFLICT (user_id, date)
    DO UPDATE SET new_connections = profile_analytics.new_connections + 1;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_connection_analytics ON connections;
CREATE TRIGGER trg_connection_analytics
  AFTER UPDATE ON connections
  FOR EACH ROW EXECUTE FUNCTION profile_analytics_on_connection_accepted();

-- ─── POST ENGAGEMENT ─────────────────────────────────────────
-- Credits the post's author, not the reactor — post_repository.dart
-- inserts directly into post_reactions on toggle, so this is an
-- AFTER INSERT trigger, not something callable from the client. Insert
-- -only by design: like record_profile_view(), this counts engagement
-- events received, not a live gauge, so removing a reaction later
-- shouldn't erase that the engagement happened. Self-reactions don't
-- count, mirroring the self-view guard in record_profile_view().
CREATE OR REPLACE FUNCTION profile_analytics_on_reaction()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE post_author UUID;
BEGIN
  SELECT author_id INTO post_author FROM posts WHERE id = NEW.post_id;
  IF post_author IS NULL OR post_author = NEW.user_id THEN RETURN NEW; END IF;

  INSERT INTO profile_analytics (user_id, date, post_reactions)
  VALUES (post_author, CURRENT_DATE, 1)
  ON CONFLICT (user_id, date)
  DO UPDATE SET post_reactions = profile_analytics.post_reactions + 1;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_reaction_analytics ON post_reactions;
CREATE TRIGGER trg_reaction_analytics
  AFTER INSERT ON post_reactions
  FOR EACH ROW EXECUTE FUNCTION profile_analytics_on_reaction();
