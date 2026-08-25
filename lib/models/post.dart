import 'profile.dart';

/// A row from `posts`, optionally with its author and engagement counts
/// joined in by the embedded select in `PostRepository`.
///
/// Bounties are not a separate table — a post with [isBounty] set carries
/// [bountyPoints], and the payout happens when the asker accepts an answer
/// through the `accept_bounty_solution` RPC.
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.type,
    required this.content,
    required this.createdAt,
    this.author,
    this.codeLanguage,
    this.codeSnippet,
    this.videoUrl,
    this.thumbnailUrl,
    this.isFlagged = false,
    this.isBounty = false,
    this.bountyPoints = 0,
    this.bountySolved = false,
    this.bountyModule,
    this.reactionCount = 0,
    this.commentCount = 0,
    this.myReaction,
  });

  final String id;
  final String authorId;
  final String type;
  final String content;
  final DateTime createdAt;
  final Profile? author;
  final String? codeLanguage;
  final String? codeSnippet;
  final String? videoUrl;
  final String? thumbnailUrl;
  final bool isFlagged;
  final bool isBounty;
  final int bountyPoints;
  final bool bountySolved;
  final String? bountyModule;
  final int reactionCount;
  final int commentCount;

  /// The emoji this user reacted with, or null. Filled in separately because
  /// PostgREST cannot filter an embedded row to the current user.
  final String? myReaction;

  bool get hasCode => (codeSnippet?.trim().isNotEmpty ?? false);
  bool get isOpenBounty => isBounty && !bountySolved;

  factory Post.fromMap(Map<String, dynamic> map) => Post(
        id: map['id'] as String,
        authorId: map['author_id'] as String,
        type: (map['type'] ?? 'TEXT') as String,
        content: (map['content'] ?? '') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ?? DateTime.now(),
        author: map['author'] is Map<String, dynamic>
            ? Profile.fromMap(map['author'] as Map<String, dynamic>)
            : null,
        codeLanguage: map['code_language'] as String?,
        codeSnippet: map['code_snippet'] as String?,
        videoUrl: map['video_url'] as String?,
        thumbnailUrl: map['thumbnail_url'] as String?,
        isFlagged: (map['is_flagged'] as bool?) ?? false,
        isBounty: (map['is_bounty'] as bool?) ?? false,
        bountyPoints: (map['bounty_points'] as int?) ?? 0,
        bountySolved: (map['bounty_solved'] as bool?) ?? false,
        bountyModule: map['bounty_module'] as String?,
        reactionCount: embeddedCount(map['post_reactions']),
        commentCount: embeddedCount(map['comments']),
      );

  Post copyWith({
    int? reactionCount,
    int? commentCount,
    bool? bountySolved,
    String? myReaction,
    bool clearMyReaction = false,
  }) =>
      Post(
        id: id,
        authorId: authorId,
        type: type,
        content: content,
        createdAt: createdAt,
        author: author,
        codeLanguage: codeLanguage,
        codeSnippet: codeSnippet,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        isFlagged: isFlagged,
        isBounty: isBounty,
        bountyPoints: bountyPoints,
        bountySolved: bountySolved ?? this.bountySolved,
        bountyModule: bountyModule,
        reactionCount: reactionCount ?? this.reactionCount,
        commentCount: commentCount ?? this.commentCount,
        myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
      );
}

/// A row from `comments`. `isSolution` is set only by the
/// `accept_bounty_solution` RPC — writing it directly is stripped by
/// `trg_comments_guard`.
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.author,
    this.isSolution = false,
    this.parentId,
  });

  final String id;
  final String postId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final Profile? author;
  final bool isSolution;
  final String? parentId;

  factory Comment.fromMap(Map<String, dynamic> map) => Comment(
        id: map['id'] as String,
        postId: map['post_id'] as String,
        authorId: map['author_id'] as String,
        content: (map['content'] ?? '') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ?? DateTime.now(),
        author: map['author'] is Map<String, dynamic>
            ? Profile.fromMap(map['author'] as Map<String, dynamic>)
            : null,
        isSolution: (map['is_solution'] as bool?) ?? false,
        parentId: map['parent_id'] as String?,
      );
}
