import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../models/profile.dart';
import '../models/social.dart';

/// Replaces `/api/connections`.
class ConnectionRepository {
  const ConnectionRepository();

  static const _select = '''
    *,
    sender:profiles!sender_id(id, full_name, avatar_url, role, course, company_name),
    receiver:profiles!receiver_id(id, full_name, avatar_url, role, course, company_name)
  ''';

  Future<List<Connection>> accepted() async {
    final me = requireUserId;
    final rows = await db
        .from('connections')
        .select(_select)
        .eq('status', 'ACCEPTED')
        .or('sender_id.eq.$me,receiver_id.eq.$me');
    return rows.map(Connection.fromMap).toList();
  }

  /// Requests waiting on *this* user to answer.
  Future<List<Connection>> incomingRequests() async {
    final rows = await db
        .from('connections')
        .select(_select)
        .eq('receiver_id', requireUserId)
        .eq('status', 'PENDING')
        .order('created_at', ascending: false);
    return rows.map(Connection.fromMap).toList();
  }

  /// The connection row between the current user and [otherId], either
  /// direction, or null if they have never interacted.
  Future<Connection?> between(String otherId) async {
    final me = requireUserId;
    final rows = await db.from('connections').select(_select).or(
          'and(sender_id.eq.$me,receiver_id.eq.$otherId),'
          'and(sender_id.eq.$otherId,receiver_id.eq.$me)',
        );
    return rows.isEmpty ? null : Connection.fromMap(rows.first);
  }

  Future<void> request(String targetId) => db.from('connections').insert({
        'sender_id': requireUserId,
        'receiver_id': targetId,
      });

  Future<void> respond(String connectionId, {required bool accept}) =>
      db.from('connections').update({
        'status': accept ? 'ACCEPTED' : 'DECLINED',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', connectionId);

  Future<void> remove(String connectionId) =>
      db.from('connections').delete().eq('id', connectionId);
}

/// Replaces `/api/messages` and the Socket.IO chat handlers.
///
/// Live updates come from Supabase Realtime instead of a socket server.
/// Realtime applies RLS per subscriber, so a channel on `messages` only ever
/// delivers rows where the user is the sender or the receiver.
class MessageRepository {
  const MessageRepository();

  /// One entry per person the user has exchanged messages with, newest first.
  ///
  /// Postgres would do this better with DISTINCT ON, but that is not
  /// expressible through PostgREST, so the thread grouping happens here.
  Future<List<Conversation>> conversations() async {
    final me = requireUserId;
    final rows = await db
        .from('messages')
        .select()
        .or('sender_id.eq.$me,receiver_id.eq.$me')
        .order('created_at', ascending: false)
        .limit(500);

    final messages = rows.map(Message.fromMap).toList();
    final latest = <String, Message>{};
    final unread = <String, int>{};

    for (final m in messages) {
      final other = m.senderId == me ? m.receiverId : m.senderId;
      latest.putIfAbsent(other, () => m); // rows are already newest-first
      if (!m.read && m.receiverId == me) {
        unread[other] = (unread[other] ?? 0) + 1;
      }
    }
    if (latest.isEmpty) return [];

    final profiles = await db
        .from('profiles')
        .select()
        .inFilter('id', latest.keys.toList());
    final byId = {
      for (final p in profiles) p['id'] as String: Profile.fromMap(p),
    };

    final result = <Conversation>[];
    for (final entry in latest.entries) {
      final profile = byId[entry.key];
      if (profile == null) continue; // profile hidden by RLS or deleted
      result.add(Conversation(
        other: profile,
        lastMessage: entry.value,
        unread: unread[entry.key] ?? 0,
      ));
    }
    result.sort((a, b) => b.lastMessage.createdAt.compareTo(a.lastMessage.createdAt));
    return result;
  }

  Future<List<Message>> thread(String otherId) async {
    final me = requireUserId;
    final rows = await db
        .from('messages')
        .select()
        .or(
          'and(sender_id.eq.$me,receiver_id.eq.$otherId),'
          'and(sender_id.eq.$otherId,receiver_id.eq.$me)',
        )
        // postgrest-dart defaults `ascending` to false (newest first),
        // unlike plain SQL — the chat screen's reverse:true ListView and the
        // realtime append in threadProvider both assume oldest-first, so this
        // must be explicit or the newest message renders at the top.
        .order('created_at', ascending: true);
    return rows.map(Message.fromMap).toList();
  }

  Future<Message> send(String toId, String content) async {
    final row = await db
        .from('messages')
        .insert({
          'sender_id': requireUserId,
          'receiver_id': toId,
          'content': content.trim(),
        })
        .select()
        .single();
    return Message.fromMap(row);
  }

  Future<void> markThreadRead(String otherId) => db
      .from('messages')
      .update({'read': true})
      .eq('sender_id', otherId)
      .eq('receiver_id', requireUserId)
      .eq('read', false);

  /// Live inserts on `messages` visible to this user.
  ///
  /// Realtime cannot express "sender OR receiver is me", so the channel
  /// subscribes to the table and RLS does the filtering; callers narrow to a
  /// single thread with [Message.inThread].
  RealtimeChannel subscribe(void Function(Message) onMessage) {
    return db
        .channel('messages:\$requireUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) => onMessage(Message.fromMap(payload.newRecord)),
        )
        .subscribe();
  }
}

/// Replaces `/api/notifications`. Every row here is written by a trigger in
/// migration 0002 — the client can only read, mark read, and delete.
class NotificationRepository {
  const NotificationRepository();

  Future<List<AppNotification>> list({int limit = 50}) async {
    final rows = await db
        .from('notifications')
        .select()
        .eq('user_id', requireUserId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<int> unreadCount() async {
    final rows = await db
        .from('notifications')
        .select('id')
        .eq('user_id', requireUserId)
        .eq('read', false);
    return rows.length;
  }

  Future<void> markRead(String id) =>
      db.from('notifications').update({'read': true}).eq('id', id);

  Future<void> markAllRead() => db
      .from('notifications')
      .update({'read': true})
      .eq('user_id', requireUserId)
      .eq('read', false);

  Future<void> remove(String id) =>
      db.from('notifications').delete().eq('id', id);

  RealtimeChannel subscribe(void Function(AppNotification) onNotification) {
    final me = requireUserId;
    return db
        .channel('notifications:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: me,
          ),
          callback: (payload) =>
              onNotification(AppNotification.fromMap(payload.newRecord)),
        )
        .subscribe();
  }
}
