import '../core/supabase.dart';
import '../models/post.dart';

/// Replaces `/api/posts`.
///
/// The embedded selects here are the same PostgREST joins the Express routes
/// used (`author:profiles!author_id(...)`), just issued straight from the app.
class PostRepository {
  const PostRepository();

  static const _postSelect = '''
    *,
    author:profiles!author_id(id, full_name, avatar_url, role, course, faculty, company_name),
    post_reactions(count),
    comments(count)
  ''';

  /// The connection-scoped feed: posts by people you are connected to, plus
  /// your own. Mirrors `GET /api/posts/feed`.
  ///
  /// Two round-trips rather than one join, because the connection is symmetric
  /// and PostgREST cannot express "the other side of my accepted connections"
  /// as an embedded filter.
  Future<List<Post>> feed({int page = 0, int pageSize = 20}) async {
    final me = requireUserId;

    final conns = await db
        .from('connections')
        .select('sender_id, receiver_id')
        .eq('status', 'ACCEPTED')
        .or('sender_id.eq.$me,receiver_id.eq.$me');

    final authorIds = <String>{me};
    for (final c in conns) {
      authorIds.add(c['sender_id'] == me
          ? c['receiver_id'] as String
          : c['sender_id'] as String);
    }

    final from = page * pageSize;
    final rows = await db
        .from('posts')
        .select(_postSelect)
        .inFilter('author_id', authorIds.toList())
        .eq('is_flagged', false)
        .order('created_at', ascending: false)
        .range(from, from + pageSize - 1);

    return _withMyReactions(rows.map(Post.fromMap).toList());
  }

  /// Everything public, for when the feed is empty because the user has not
  /// connected to anyone yet. The old app had no equivalent and new students
  /// landed on a blank screen.
  Future<List<Post>> discover({int page = 0, int pageSize = 20}) async {
    final from = page * pageSize;
    final rows = await db
        .from('posts')
        .select(_postSelect)
        .eq('is_flagged', false)
        .order('created_at', ascending: false)
        .range(from, from + pageSize - 1);
    return _withMyReactions(rows.map(Post.fromMap).toList());
  }

  /// Open bounties, highest value first. Mirrors `GET /api/posts/bounties`.
  ///
  /// [faculty] filters on the *author's* faculty, which lives on the embedded
  /// profile rather than on `posts`, so it is applied after the fetch.
  Future<List<Post>> bounties({String? faculty}) async {
    final rows = await db
        .from('posts')
        .select(_postSelect)
        .eq('is_bounty', true)
        .eq('bounty_solved', false)
        .eq('is_flagged', false)
        .order('bounty_points', ascending: false);

    var posts = rows.map(Post.fromMap).toList();
    if (faculty != null) {
      posts = posts.where((p) => p.author?.faculty == faculty).toList();
    }
    return _withMyReactions(posts);
  }

  Future<List<Post>> byAuthor(String userId) async {
    final rows = await db
        .from('posts')
        .select(_postSelect)
        .eq('author_id', userId)
        .order('created_at', ascending: false);
    return _withMyReactions(rows.map(Post.fromMap).toList());
  }

  Future<Post> byId(String postId) async {
    final row =
        await db.from('posts').select(_postSelect).eq('id', postId).single();
    final posts = await _withMyReactions([Post.fromMap(row)]);
    return posts.first;
  }

  Future<Post> create({
    required String content,
    String type = 'TEXT',
    String? codeLanguage,
    String? codeSnippet,
    String? videoUrl,
    String? thumbnailUrl,
    bool isBounty = false,
    String? bountyModule,
    List<String>? attachmentUrls,
  }) async {
    // bounty_points / bounty_solved / is_flagged are set by trg_posts_guard;
    // sending them from here would be ignored anyway.
    final row = await db
        .from('posts')
        .insert({
          'author_id': requireUserId,
          'type': type,
          'content': content.trim(),
          'code_language': codeLanguage,
          'code_snippet': codeSnippet,
          'video_url': videoUrl,
          'thumbnail_url': thumbnailUrl,
          'is_bounty': isBounty,
          'bounty_module': bountyModule,
          'attachment_urls': attachmentUrls,
        })
        .select(_postSelect)
        .single();
    return Post.fromMap(row);
  }

  Future<void> delete(String postId) =>
      db.from('posts').delete().eq('id', postId);

  /// Toggles this user's reaction. Returns the emoji now in place, or null if
  /// the reaction was removed.
  Future<String?> toggleReaction(String postId, {String emoji = '👍'}) async {
    final me = requireUserId;
    final existing = await db
        .from('post_reactions')
        .select('id, emoji')
        .eq('post_id', postId)
        .eq('user_id', me)
        .maybeSingle();

    if (existing != null) {
      if (existing['emoji'] == emoji) {
        await db.from('post_reactions').delete().eq('id', existing['id']);
        return null;
      }
      await db
          .from('post_reactions')
          .update({'emoji': emoji}).eq('id', existing['id']);
      return emoji;
    }

    await db.from('post_reactions').insert({
      'post_id': postId,
      'user_id': me,
      'emoji': emoji,
    });
    return emoji;
  }

  Future<List<Comment>> comments(String postId) async {
    final rows = await db
        .from('comments')
        .select(
            '*, author:profiles!author_id(id, full_name, avatar_url, role, course)')
        .eq('post_id', postId)
        .order('created_at');
    return rows.map(Comment.fromMap).toList();
  }

  Future<Comment> addComment(
    String postId, {
    required String content,
    String? parentId,
  }) async {
    final row = await db
        .from('comments')
        .insert({
          'post_id': postId,
          'author_id': requireUserId,
          'content': content.trim(),
          'parent_id': parentId,
        })
        .select(
            '*, author:profiles!author_id(id, full_name, avatar_url, role, course)')
        .single();
    return Comment.fromMap(row);
  }

  Future<void> deleteComment(String commentId) =>
      db.from('comments').delete().eq('id', commentId);

  /// Awards the bounty to a comment's author.
  ///
  /// Goes through an RPC because the payout writes to `logic_points`, which
  /// has no client INSERT policy at all — and because only the person who
  /// posted the bounty may accept, which the function verifies server-side.
  Future<void> acceptSolution(String commentId) =>
      db.rpc('accept_bounty_solution', params: {'p_comment_id': commentId});

  Future<void> flagPost(String postId, String reason) =>
      db.from('content_flags').insert({
        'reporter_id': requireUserId,
        'post_id': postId,
        'reason': reason,
      });

  /// Fills in `myReaction` for a page of posts with one extra query, so the
  /// UI can show which emoji the user already picked.
  Future<List<Post>> _withMyReactions(List<Post> posts) async {
    if (posts.isEmpty) return posts;
    final me = currentUserId;
    if (me == null) return posts;

    final rows = await db
        .from('post_reactions')
        .select('post_id, emoji')
        .eq('user_id', me)
        .inFilter('post_id', posts.map((p) => p.id).toList());

    final mine = {
      for (final r in rows) r['post_id'] as String: r['emoji'] as String,
    };
    return [
      for (final p in posts)
        mine.containsKey(p.id) ? p.copyWith(myReaction: mine[p.id]) : p,
    ];
  }
}
