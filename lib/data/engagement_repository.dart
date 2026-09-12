import '../core/supabase.dart';
import '../models/opportunity.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/recommendation.dart';

/// Recommendations, saved items, search and suggestions — the §2.3 profile
/// requirements plus the handful of things any professional network is
/// expected to have.
///
/// A separate repository rather than more methods on ProfileRepository,
/// because none of this is *about* a profile row: recommendations are a
/// relationship between two people, saves are private bookmarks, and search
/// spans three tables.
class EngagementRepository {
  const EngagementRepository();

  static const _withPeople = '''
    *,
    author:profiles!author_id(id, full_name, avatar_url, role, course, company_name, headline),
    subject:profiles!subject_id(id, full_name, avatar_url, role, course, company_name)
  ''';

  // ─── Recommendations (§2.3) ────────────────────────────────

  /// Approved recommendations on someone's profile. For your own profile the
  /// policy also returns pending ones, which is how the approval queue works
  /// without a second query.
  Future<List<Recommendation>> forSubject(String userId) async {
    final rows = await db
        .from('recommendations')
        .select(_withPeople)
        .eq('subject_id', userId)
        .order('created_at', ascending: false);
    return rows.map(Recommendation.fromMap).toList();
  }

  /// What the signed-in user has written about others.
  Future<List<Recommendation>> written() async {
    final rows = await db
        .from('recommendations')
        .select(_withPeople)
        .eq('author_id', requireUserId)
        .order('created_at', ascending: false);
    return rows.map(Recommendation.fromMap).toList();
  }

  /// Waiting on the signed-in user to approve.
  Future<List<Recommendation>> pendingForMe() async {
    final rows = await db
        .from('recommendations')
        .select(_withPeople)
        .eq('subject_id', requireUserId)
        .eq('approved', false)
        .order('created_at', ascending: false);
    return rows.map(Recommendation.fromMap).toList();
  }

  /// `approved` is stripped on insert by `trg_recommendations_guard`, so
  /// there is no way to write one that is live on arrival.
  Future<void> write({
    required String subjectId,
    required String body,
    String? relationship,
  }) =>
      db.from('recommendations').insert({
        'author_id': requireUserId,
        'subject_id': subjectId,
        'body': body.trim(),
        'relationship': relationship?.trim(),
      });

  /// Subject-only. The trigger reverts `approved` for anyone else, so a
  /// misrouted call fails silently rather than dangerously.
  Future<void> setApproved(String id, bool approved) =>
      db.from('recommendations').update({'approved': approved}).eq('id', id);

  Future<void> remove(String id) =>
      db.from('recommendations').delete().eq('id', id);

  // ─── Saved items ───────────────────────────────────────────

  Future<void> savePost(String postId) => db.from('saved_items').insert({
        'user_id': requireUserId,
        'post_id': postId,
      });

  Future<void> saveOpportunity(String opportunityId) =>
      db.from('saved_items').insert({
        'user_id': requireUserId,
        'opportunity_id': opportunityId,
      });

  Future<void> unsavePost(String postId) => db
      .from('saved_items')
      .delete()
      .eq('user_id', requireUserId)
      .eq('post_id', postId);

  Future<void> unsaveOpportunity(String opportunityId) => db
      .from('saved_items')
      .delete()
      .eq('user_id', requireUserId)
      .eq('opportunity_id', opportunityId);

  /// The ids the user has saved, for marking cards in a list.
  ///
  /// One query rather than a per-card check: the alternative is a round-trip
  /// per row, which on a twenty-post feed is twenty requests to render a
  /// bookmark icon.
  Future<Set<String>> savedIds() async {
    final rows = await db
        .from('saved_items')
        .select('post_id, opportunity_id')
        .eq('user_id', requireUserId);
    return {
      for (final row in rows)
        if (row['post_id'] != null)
          row['post_id'] as String
        else if (row['opportunity_id'] != null)
          row['opportunity_id'] as String,
    };
  }

  Future<List<Post>> savedPosts() async {
    final rows = await db
        .from('saved_items')
        .select('created_at, posts!post_id(*, '
            'author:profiles!author_id(id, full_name, avatar_url, role, course, faculty, company_name), '
            'post_reactions(count), comments(count))')
        .eq('user_id', requireUserId)
        .not('post_id', 'is', null)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        if (row['posts'] is Map<String, dynamic>)
          Post.fromMap(row['posts'] as Map<String, dynamic>),
    ];
  }

  Future<List<Opportunity>> savedOpportunities() async {
    final rows = await db
        .from('saved_items')
        .select('created_at, opportunities!opportunity_id(*, '
            'business:profiles!business_id(id, full_name, avatar_url, role, company_name, industry, company_location))')
        .eq('user_id', requireUserId)
        .not('opportunity_id', 'is', null)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        if (row['opportunities'] is Map<String, dynamic>)
          Opportunity.fromMap(row['opportunities'] as Map<String, dynamic>),
    ];
  }

  // ─── Search and suggestions ────────────────────────────────

  /// People, posts and opportunities in one call.
  ///
  /// `search_everything()` is SECURITY INVOKER, so each arm still runs under
  /// the caller's policies — faculty scoping from 0007 applies without the
  /// function having to know about it.
  Future<List<SearchHit>> search(String term, {int limit = 10}) async {
    final clean = term.trim();
    if (clean.isEmpty) return const [];

    final rows = await db.rpc('search_everything', params: {
      'p_term': clean,
      'p_limit': limit,
    }) as List;
    return rows.cast<Map<String, dynamic>>().map(SearchHit.fromMap).toList();
  }

  /// "People you may know", with the reason attached — a suggestion you
  /// cannot explain is indistinguishable from a random name.
  Future<List<ConnectionSuggestion>> suggestions({int limit = 10}) async {
    final scored = await db.rpc('suggested_connections', params: {
      'p_limit': limit,
    }) as List;
    if (scored.isEmpty) return const [];

    final byId = {
      for (final row in scored) row['id'] as String: row,
    };

    final profiles = await db
        .from('profiles')
        .select()
        .inFilter('id', byId.keys.toList());

    final out = <ConnectionSuggestion>[];
    for (final row in profiles) {
      final meta = byId[row['id'] as String];
      if (meta == null) continue;
      out.add(ConnectionSuggestion(
        profile: Profile.fromMap(row),
        score: (meta['score'] as num?)?.toInt() ?? 0,
        reason: (meta['reason'] ?? 'Suggested for you') as String,
      ));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  // ─── Profile visibility (§2.3) ─────────────────────────────

  /// Someone else's profile, with hidden sections already removed.
  ///
  /// Goes through `profile_for_viewer()` rather than selecting the row: a
  /// hidden section has to be *absent from the response*, not merely
  /// unrendered, or the data is still on the device and the control is
  /// decorative — which the guidelines call out by name.
  Future<Profile?> profileForViewer(String userId) async {
    final row = await db.rpc('profile_for_viewer', params: {'target': userId});
    if (row == null) return null;
    return Profile.fromMap(Map<String, dynamic>.from(row as Map));
  }
}
