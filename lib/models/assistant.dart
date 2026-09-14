/// A row from `chat_messages` — one turn in a user's conversation with the
/// AI assistant (migration 0009).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String userId;

  /// Either `'user'` or `'assistant'` — matches the CHECK constraint on the
  /// column, so this is never anything else.
  final String role;
  final String content;
  final DateTime createdAt;

  bool get isFromUser => role == 'user';

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        role: map['role'] as String,
        content: map['content'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

/// A row from `onboarding_progress` (present since migration 0001) — where a
/// user is in the first-run profile walkthrough, and whether they have
/// already seen the app tutorial.
class OnboardingProgress {
  const OnboardingProgress({
    required this.userId,
    required this.profileStep,
    required this.tutorialComplete,
    this.completedAt,
  });

  final String userId;
  final int profileStep;
  final bool tutorialComplete;
  final DateTime? completedAt;

  factory OnboardingProgress.fromMap(Map<String, dynamic> map) =>
      OnboardingProgress(
        userId: map['user_id'] as String,
        profileStep: (map['profile_step'] ?? 0) as int,
        tutorialComplete: (map['tutorial_complete'] ?? false) as bool,
        completedAt: map['completed_at'] == null
            ? null
            : DateTime.tryParse(map['completed_at'] as String),
      );
}
