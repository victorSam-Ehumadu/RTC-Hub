import 'profile.dart';

/// A written recommendation or testimonial — §2.3.
///
/// Not visible on the subject's profile until they approve it. That is not a
/// nicety: a profile is a professional record, and letting anyone staple text
/// to someone else's is a harassment vector rather than a feature. The
/// approval is enforced by `trg_recommendations_guard` (migration 0011),
/// which also stops an author approving their own and a subject rewriting
/// words attributed to someone else.
class Recommendation {
  const Recommendation({
    required this.id,
    required this.authorId,
    required this.subjectId,
    required this.body,
    required this.createdAt,
    this.relationship,
    this.approved = false,
    this.author,
    this.subject,
  });

  final String id;
  final String authorId;
  final String subjectId;
  final String body;
  final DateTime createdAt;

  /// How the author knows them — "Lectured me", "Worked together at Nexford".
  final String? relationship;

  final bool approved;
  final Profile? author;
  final Profile? subject;

  bool get isPending => !approved;

  factory Recommendation.fromMap(Map<String, dynamic> map) => Recommendation(
        id: map['id'] as String,
        authorId: map['author_id'] as String,
        subjectId: map['subject_id'] as String,
        body: (map['body'] ?? '') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ??
                DateTime.now(),
        relationship: map['relationship'] as String?,
        approved: (map['approved'] as bool?) ?? false,
        author: map['author'] is Map<String, dynamic>
            ? Profile.fromMap(map['author'] as Map<String, dynamic>)
            : null,
        subject: map['subject'] is Map<String, dynamic>
            ? Profile.fromMap(map['subject'] as Map<String, dynamic>)
            : null,
      );
}

/// One hit from `search_everything()`.
///
/// People, posts and opportunities arrive in a single call so the UI can show
/// one ranked list instead of three tabs each with their own spinner.
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.extra = const {},
  });

  /// 'profile', 'post' or 'opportunity'.
  final String kind;
  final String id;
  final String title;
  final String? subtitle;
  final Map<String, dynamic> extra;

  bool get isProfile => kind == 'profile';
  bool get isPost => kind == 'post';
  bool get isOpportunity => kind == 'opportunity';

  /// Where tapping it should go.
  String get route => switch (kind) {
        'profile' => '/user/$id',
        'post' => '/post/$id',
        _ => '/opportunities',
      };

  factory SearchHit.fromMap(Map<String, dynamic> map) => SearchHit(
        kind: (map['kind'] ?? '') as String,
        id: map['id'] as String,
        title: (map['title'] ?? '') as String,
        subtitle: map['subtitle'] as String?,
        extra: map['extra'] is Map
            ? Map<String, dynamic>.from(map['extra'] as Map)
            : const {},
      );
}

/// A "people you may know" entry, with the reason it was suggested.
///
/// The reason is shown to the user: a suggestion you cannot explain is
/// indistinguishable from a random name.
class ConnectionSuggestion {
  const ConnectionSuggestion({
    required this.profile,
    required this.score,
    required this.reason,
  });

  final Profile profile;
  final int score;
  final String reason;
}
