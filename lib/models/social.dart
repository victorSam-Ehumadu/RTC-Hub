import 'profile.dart';

/// A row from `connections`. The relationship is symmetric once accepted, so
/// [other] resolves whichever side is not the current user.
class Connection {
  const Connection({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    this.sender,
    this.receiver,
    this.createdAt,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final Profile? sender;
  final Profile? receiver;
  final DateTime? createdAt;

  bool get isAccepted => status == 'ACCEPTED';
  bool get isPending => status == 'PENDING';

  String otherId(String me) => senderId == me ? receiverId : senderId;
  Profile? other(String me) => senderId == me ? receiver : sender;

  factory Connection.fromMap(Map<String, dynamic> map) => Connection(
        id: map['id'] as String,
        senderId: map['sender_id'] as String,
        receiverId: map['receiver_id'] as String,
        status: (map['status'] ?? 'PENDING') as String,
        sender: map['sender'] is Map<String, dynamic>
            ? Profile.fromMap(map['sender'] as Map<String, dynamic>)
            : null,
        receiver: map['receiver'] is Map<String, dynamic>
            ? Profile.fromMap(map['receiver'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.tryParse((map['created_at'] ?? '') as String),
      );
}

/// A row from `messages`.
class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime createdAt;
  final bool read;

  bool isMine(String me) => senderId == me;

  /// True when this message belongs to the thread between [me] and [them].
  bool inThread(String me, String them) =>
      (senderId == me && receiverId == them) ||
      (senderId == them && receiverId == me);

  factory Message.fromMap(Map<String, dynamic> map) => Message(
        id: map['id'] as String,
        senderId: map['sender_id'] as String,
        receiverId: map['receiver_id'] as String,
        content: (map['content'] ?? '') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ?? DateTime.now(),
        read: (map['read'] as bool?) ?? false,
      );
}

/// One chat thread, summarised for the conversations list.
class Conversation {
  const Conversation({
    required this.other,
    required this.lastMessage,
    required this.unread,
  });

  final Profile other;
  final Message lastMessage;
  final int unread;
}

/// A row from `notifications`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.data,
    this.read = false,
  });

  final String id;
  final String type;
  final String title;
  final DateTime createdAt;
  final String? body;
  final Map<String, dynamic>? data;
  final bool read;

  String? get postId => data?['post_id'] as String?;
  String? get senderId => data?['sender_id'] as String?;
  String? get opportunityId => data?['opportunity_id'] as String?;

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        type: (map['type'] ?? '') as String,
        title: (map['title'] ?? '') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ?? DateTime.now(),
        body: map['body'] as String?,
        data: map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : null,
        read: (map['read'] as bool?) ?? false,
      );
}
