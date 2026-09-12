import '../core/supabase.dart';
import '../models/opportunity.dart';
import '../models/profile.dart';

/// Replaces `/api/admin` and `/api/analytics`.
///
/// Nothing here carries special credentials. Every call relies on `is_admin()`
/// inside an RLS policy or a SECURITY DEFINER function, so a non-admin running
/// the same code gets an empty result or a permission error.
class AdminRepository {
  const AdminRepository();

  Future<List<Profile>> users({String? status, String? role}) async {
    var query = db.from('profiles').select();
    if (status != null) query = query.eq('status', status);
    if (role != null) query = query.eq('role', role);
    final rows = await query.order('created_at', ascending: false);
    return rows.map(Profile.fromMap).toList();
  }

  Future<List<Profile>> pendingUsers() => users(status: 'PENDING');

  /// Approve, suspend or reject an account.
  ///
  /// `trg_profiles_guard` allows this only when `is_admin()` holds, and
  /// `trg_profile_status_notify` tells the user what happened.
  Future<void> setUserStatus(String userId, String status) =>
      db.from('profiles').update({'status': status}).eq('id', userId);

  Future<void> deleteUser(String userId) =>
      db.from('profiles').delete().eq('id', userId);

  /// Listings waiting for review, plus their business.
  Future<List<Opportunity>> pendingOpportunities() async {
    final rows = await db
        .from('opportunities')
        .select(
            '*, business:profiles!business_id(id, full_name, avatar_url, role, company_name, industry)')
        .eq('status', 'PENDING')
        .order('created_at', ascending: false);
    return rows.map(Opportunity.fromMap).toList();
  }

  Future<void> setOpportunityStatus(String id, String status) =>
      db.from('opportunities').update({'status': status}).eq('id', id);

  Future<List<Map<String, dynamic>>> openFlags() async {
    final rows = await db
        .from('content_flags')
        .select(
            '*, reporter:profiles!reporter_id(id, full_name, avatar_url), post:posts!post_id(id, content, author_id)')
        .eq('resolved', false)
        .order('created_at', ascending: false);
    return rows;
  }

  /// Resolving a flag optionally hides the post. `is_flagged` is admin-only —
  /// `trg_posts_guard` reverts the field for everyone else.
  Future<void> resolveFlag(String flagId, {String? postId, bool hidePost = false}) async {
    if (hidePost && postId != null) {
      await db.from('posts').update({'is_flagged': true}).eq('id', postId);
    }
    await db.from('content_flags').update({
      'resolved': true,
      'resolved_by': requireUserId,
    }).eq('id', flagId);
  }

  Future<void> announce({
    required String title,
    required String body,
    List<String>? targetRoles,
  }) =>
      db.rpc('broadcast_announcement', params: {
        'p_title': title.trim(),
        'p_body': body.trim(),
        'p_target_roles': targetRoles,
      });

  /// Headline counts for the admin dashboard.
  ///
  /// One RPC rather than six queries whose row counts were taken in Dart.
  /// PostgREST caps a result set at 1000, so the old version reported
  /// "1000 users" forever once the project passed that — a dashboard that
  /// lies quietly is worse than one that errors.
  Future<AdminStats> stats() async {
    final row = await db.rpc('admin_stats') as Map<String, dynamic>;
    int at(String key) => (row[key] as num?)?.toInt() ?? 0;

    return AdminStats(
      totalUsers: at('total_users'),
      pendingUsers: at('pending_users'),
      totalPosts: at('total_posts'),
      bounties: at('bounties'),
      pendingOpportunities: at('pending_opportunities'),
      openFlags: at('open_flags'),
    );
  }
}

class AdminStats {
  const AdminStats({
    required this.totalUsers,
    required this.pendingUsers,
    required this.totalPosts,
    required this.bounties,
    required this.pendingOpportunities,
    required this.openFlags,
  });

  final int totalUsers;
  final int pendingUsers;
  final int totalPosts;
  final int bounties;
  final int pendingOpportunities;
  final int openFlags;
}

/// Replaces `/api/analytics/student` — the numbers behind the profile's
/// analytics tab.
class AnalyticsRepository {
  const AnalyticsRepository();

  Future<StudentStats> forStudent(String userId) async {
    final results = await Future.wait<dynamic>([
      db.rpc('total_logic_points', params: {'uid': userId}),
      db.from('posts').select('id').eq('author_id', userId),
      db.from('skills').select('id').eq('user_id', userId),
      db
          .from('connections')
          .select('id')
          .eq('status', 'ACCEPTED')
          .or('sender_id.eq.$userId,receiver_id.eq.$userId'),
      db
          .from('profile_analytics')
          .select('date, profile_views, new_connections, post_reactions')
          .eq('user_id', userId)
          .order('date', ascending: false)
          .limit(30),
      db.from('profiles').select('course, profile_completeness').eq('id', userId).maybeSingle(),
      db.rpc('my_searched_skills', params: {'p_limit': 8}),
    ]);

    final daily = (results[4] as List).cast<Map<String, dynamic>>();
    int sumOf(String column) => daily.fold<int>(
          0,
          (sum, row) => sum + ((row[column] as int?) ?? 0),
        );
    List<DailyMetric> seriesOf(String column) => daily.reversed
        .map((row) => DailyMetric(
              date: DateTime.tryParse((row['date'] ?? '') as String) ??
                  DateTime.now(),
              value: (row[column] as int?) ?? 0,
            ))
        .toList();

    final me = results[5] as Map<String, dynamic>?;
    final course = me?['course'] as String?;
    final myCompleteness = (me?['profile_completeness'] as num?)?.toInt() ?? 0;

    double programmeAvg = 0;
    int programmePeers = 0;
    if (course != null && course.isNotEmpty) {
      final row = await db.rpc('programme_completeness', params: {'p_course': course});
      final peers = (row as List).isNotEmpty ? row.first as Map<String, dynamic> : null;
      programmeAvg = (peers?['avg_completeness'] as num?)?.toDouble() ?? 0;
      programmePeers = (peers?['peer_count'] as num?)?.toInt() ?? 0;
    }

    List<SkillCount> parseSkillCounts(
      List<dynamic> rows,
      String nameKey,
      String countKey,
    ) =>
        rows
            .cast<Map<String, dynamic>>()
            .map((row) => SkillCount(
                  skill: row[nameKey] as String,
                  count: (row[countKey] as num).toInt(),
                ))
            .toList();

    return StudentStats(
      logicPoints: (results[0] as num?)?.toInt() ?? 0,
      posts: (results[1] as List).length,
      skills: (results[2] as List).length,
      connections: (results[3] as List).length,
      profileViews: sumOf('profile_views'),
      newConnections: sumOf('new_connections'),
      postReactions: sumOf('post_reactions'),
      viewsByDay: seriesOf('profile_views'),
      connectionsByDay: seriesOf('new_connections'),
      engagementByDay: seriesOf('post_reactions'),
      myCompleteness: myCompleteness,
      programmeAvgCompleteness: programmeAvg,
      programmePeerCount: programmePeers,
      mySearchedSkills:
          parseSkillCounts(results[6] as List, 'skill_name', 'search_count'),
    );
  }

  /// Platform-wide — not user-specific, so this is a separate call from
  /// [forStudent]. A bonus signal beyond §2.7's literal text (which only
  /// asks for a student's own skills as searched by business users, now
  /// [StudentStats.mySearchedSkills]): what businesses ask for across
  /// active listings, for context on what's in demand generally.
  Future<List<SkillCount>> wantedSkills() async {
    final rows = await db.rpc('top_wanted_skills', params: {'p_limit': 8});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((row) => SkillCount(
              skill: row['skill'] as String,
              count: (row['listings'] as num).toInt(),
            ))
        .toList();
  }
}

class StudentStats {
  const StudentStats({
    required this.logicPoints,
    required this.posts,
    required this.skills,
    required this.connections,
    required this.profileViews,
    required this.newConnections,
    required this.postReactions,
    required this.viewsByDay,
    required this.connectionsByDay,
    required this.engagementByDay,
    required this.myCompleteness,
    required this.programmeAvgCompleteness,
    required this.programmePeerCount,
    required this.mySearchedSkills,
  });

  final int logicPoints;
  final int posts;
  final int skills;
  final int connections;
  final int profileViews;

  /// Last 30 days — new ACCEPTED connections and reactions received,
  /// summed from [connectionsByDay]/[engagementByDay]. Distinct from
  /// [connections], which is the all-time total.
  final int newConnections;
  final int postReactions;

  final List<DailyMetric> viewsByDay;
  final List<DailyMetric> connectionsByDay;
  final List<DailyMetric> engagementByDay;

  /// Profile completeness (0-100) versus other STUDENT profiles sharing
  /// [Profile.course] — see `programme_completeness()` (migration 0007).
  /// [programmePeerCount] is 0 when the student has no course set, or has
  /// no visible classmates yet; the dashboard should fall back to just
  /// showing [myCompleteness] in that case.
  final int myCompleteness;
  final double programmeAvgCompleteness;
  final int programmePeerCount;

  /// §2.7, literally: "which of their skills are most searched for by
  /// business users" — the caller's own skills only, ranked by how often a
  /// BUSINESS-role search matched them. See `my_searched_skills()`
  /// (migration 0008), which corrected this from an earlier, wrongly
  /// platform-wide version.
  final List<SkillCount> mySearchedSkills;
}

/// One point in a 30-day daily series — profile views, new connections, or
/// post engagement, depending on which [StudentStats] field it came from.
class DailyMetric {
  const DailyMetric({required this.date, required this.value});

  final DateTime date;
  final int value;
}

class SkillCount {
  const SkillCount({required this.skill, required this.count});

  final String skill;
  final int count;
}
