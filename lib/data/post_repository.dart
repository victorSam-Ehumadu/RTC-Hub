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
  /// your own.
  ///
  /// Resolving the symmetric connection graph moved into `feed_post_ids()` in
  /// migration 0007 — doing it in Dart meant pulling every connection row to
  /// the device first, and it could not express faculty scoping at all. The
  /// function is SECURITY INVOKER, so `posts_select` still applies inside it
  /// and a Business student cannot be handed IT ids.
  Future<List<Post>> feed({int page = 0, int pageSize = 20}) async {
    final ids = await db.rpc('feed_post_ids', params: {
      'p_limit': pageSize,
      'p_offset': page * pageSize,
    }) as List;
    if (ids.isEmpty) return [];

    return _byIdsInOrder([
      for (final row in ids) row['post_id'] as String,
    ]);
  }

  /// Relevance-ranked discovery, for when the connection feed is empty or
  /// thin. §2.4 asks for a feed ranked by relevance that behaves differently
  /// per role; the scoring lives in `ranked_feed()` so it runs next to the
  /// data rather than re-sorting a page on the device.
  Future<List<Post>> discover({int page = 0, int pageSize = 20}) async {
    final ranked = await db.rpc('ranked_feed', params: {
      'p_limit': pageSize,
      'p_offset': page * pageSize,
    }) as List;
    if (ranked.isEmpty) return [];

    return _byIdsInOrder([
      for (final row in ranked) row['post_id'] as String,
    ]);
  }

  /// Fetches posts by id and restores the order the ids came in — PostgREST
  /// has no way to sort by "position in this list", and the ranking is the
  /// whole point of the call that produced them.
  Future<List<Post>> _byIdsInOrder(List<String> ids) async {
    final rows = await db.from('posts').select(_postSelect).inFilter('id', ids);
    final byId = {
      for (final row in rows) row['id'] as String: Post.fromMap(row),
    };
    return _withMyReactions([
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ]);
  }

  /// Open bounties, highest value first. Mirrors `GET /api/posts/bounties`.
  ///
  /// [faculty] filters on `posts.faculty`, which 0007 denormalises from the
  /// author. RLS scopes this to the caller's own faculties regardless, so the
  /// parameter narrows within what they may already see.
  Future<List<Post>> bounties({String? faculty}) async {
    var query = db
        .from('posts')
        .select(_postSelect)
        .eq('is_bounty', true)
        .eq('bounty_solved', false)
        .eq('is_flagged', false);
    // `posts.faculty` is denormalised by trg_posts_faculty (0007), so this is
    // a real column filter now rather than a post-fetch pass over the
    // embedded author.
    if (faculty != null) query = query.eq('faculty', faculty);

    final rows = await query.order('bounty_points', ascending: false);

    return _withMyReactions(rows.map(Post.fromMap).toList());
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
    Map<String, dynamic>? sheetData,
    String? sheetName,
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
          'sheet_data': sheetData,
          'sheet_name': sheetName,
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

  /// Comments on a post. [kind] narrows to one section of a bounty thread —
  /// 'DISCUSSION' or 'SUBMISSION' — and null returns both.
  Future<List<Comment>> comments(String postId, {String? kind}) async {
    var query = db
        .from('comments')
        .select(
            '*, author:profiles!author_id(id, full_name, avatar_url, role, course)')
        .eq('post_id', postId);
    if (kind != null) query = query.eq('kind', kind);

    final rows = await query.order('created_at');
    return rows.map(Comment.fromMap).toList();
  }

  Future<Comment> addComment(
    String postId, {
    required String content,
    String? parentId,
  }) =>
      _insertComment(postId, content: content, parentId: parentId);

  /// An answer to a bounty, carrying code, a spreadsheet or an uploaded file.
  ///
  /// `trg_comments_guard` (0008) rejects a submission with none of the three,
  /// and rejects one on a post that is not a bounty — so the validation the
  /// composer does is a courtesy, not the boundary.
  Future<Comment> addSubmission(
    String postId, {
    required String content,
    String? codeLanguage,
    String? codeSnippet,
    Map<String, dynamic>? sheetData,
    String? attachmentUrl,
    String? attachmentName,
    int? attachmentSize,
    String? attachmentKind,
  }) =>
      _insertComment(
        postId,
        content: content,
        kind: 'SUBMISSION',
        extra: {
          'code_language': codeLanguage,
          'code_snippet': codeSnippet,
          'sheet_data': sheetData,
          'attachment_url': attachmentUrl,
          'attachment_name': attachmentName,
          'attachment_size': attachmentSize,
          'attachment_kind': attachmentKind,
        },
      );

  Future<Comment> _insertComment(
    String postId, {
    required String content,
    String? parentId,
    String kind = 'DISCUSSION',
    Map<String, dynamic> extra = const {},
  }) async {
    final row = await db
        .from('comments')
        .insert({
          'post_id': postId,
          'author_id': requireUserId,
          'content': content.trim(),
          'parent_id': parentId,
          'kind': kind,
          // Drop nulls rather than sending them: an explicit null would
          // overwrite a column default on a later upsert.
          ...{
            for (final entry in extra.entries)
              if (entry.value != null) entry.key: entry.value,
          },
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
