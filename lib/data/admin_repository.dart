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

  /// Looks up any profile by email, regardless of status — `profiles_select`
  /// grants an admin caller that visibility. Used to resolve an email to a
  /// user id before [promoteToAdmin].
  Future<Profile?> findByEmail(String email) async {
    final row = await db
        .from('profiles')
        .select()
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  /// Grants ADMIN and activates the account in one write.
  ///
  /// No RPC needed for this one: `profiles_update_own` already lets an admin
  /// update any row, and `trg_profiles_guard` only reverts role/status
  /// changes made by a caller who *isn't* an admin — since whoever calls
  /// this already is one, the trigger lets it straight through. That only
  /// holds once at least one admin exists to make the call; the very first
  /// admin still has to be bootstrapped by hand (see the commented block at
  /// the bottom of migration 0001) because nobody exists yet to authorize it.
  Future<void> promoteToAdmin(String userId) => db
      .from('profiles')
      .update({'role': 'ADMIN', 'status': 'ACTIVE'}).eq('id', userId);

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
  Future<AdminStats> stats() async {
    final results = await Future.wait<dynamic>([
      _count('profiles'),
      _count('profiles', column: 'status', value: 'PENDING'),
      _count('posts'),
      _count('posts', column: 'is_bounty', value: true),
      _count('opportunities', column: 'status', value: 'PENDING'),
      _count('content_flags', column: 'resolved', value: false),
    ]);
    return AdminStats(
      totalUsers: results[0],
      pendingUsers: results[1],
      totalPosts: results[2],
      bounties: results[3],
      pendingOpportunities: results[4],
      openFlags: results[5],
    );
  }

  Future<int> _count(String table, {String? column, Object? value}) async {
    var query = db.from(table).select('id');
    if (column != null) query = query.eq(column, value!);
    final rows = await query;
    return rows.length;
  }

  /// §2.7's administrator dashboard, in full except flagged content count
  /// (already a visual [AdminStats] tile): users by type, monthly active
  /// users, registrations over time, content volume, and the business
  /// approval pipeline. Every field comes from a SECURITY DEFINER RPC
  /// (migration 0009) that re-checks `is_admin()` itself, since these
  /// aggregate across every account/post/opportunity regardless of what
  /// RLS would otherwise let the caller see.
  Future<AdminDashboard> dashboard() async {
    final results = await Future.wait<dynamic>([
      db.rpc('admin_users_by_role'),
      db.rpc('admin_monthly_active_users'),
      db.rpc('admin_registrations_by_day', params: {'p_days': 30}),
      db.rpc('admin_content_volume'),
      db.rpc('admin_business_pipeline'),
    ]);

    List<CategoryCount> categories(
      List<dynamic> rows,
      String labelKey,
      String countKey,
    ) =>
        rows
            .cast<Map<String, dynamic>>()
            .map((row) => CategoryCount(
                  label: row[labelKey] as String,
                  count: (row[countKey] as num).toInt(),
                ))
            .toList();

    final byRole = categories(results[0] as List, 'role', 'total');
    final regRows = (results[2] as List).cast<Map<String, dynamic>>();

    return AdminDashboard(
      usersByRole: byRole,
      totalUsers: byRole.fold<int>(0, (sum, c) => sum + c.count),
      monthlyActiveUsers: (results[1] as num?)?.toInt() ?? 0,
      registrationsByDay: regRows
          .map((row) => DailyMetric(
                date: DateTime.tryParse((row['day'] ?? '') as String) ??
                    DateTime.now(),
                value: (row['signups'] as num).toInt(),
              ))
          .toList(),
      contentVolume: categories(results[3] as List, 'kind', 'total'),
      businessPipeline: categories(results[4] as List, 'status', 'total'),
    );
  }
}

/// The five §2.7 platform-level metrics that aren't a plain count —
/// [AdminRepository.dashboard]'s return shape for the Overview tab's chart
/// section.
class AdminDashboard {
  const AdminDashboard({
    required this.usersByRole,
    required this.totalUsers,
    required this.monthlyActiveUsers,
    required this.registrationsByDay,
    required this.contentVolume,
    required this.businessPipeline,
  });

  final List<CategoryCount> usersByRole;
  final int totalUsers;

  /// Accounts with a sign-in inside the last 30 days — see
  /// `admin_monthly_active_users()` (migration 0009).
  final int monthlyActiveUsers;
  final List<DailyMetric> registrationsByDay;

  /// Posts split by [Post.type] plus a single "OPPORTUNITY" row.
  final List<CategoryCount> contentVolume;

  /// BUSINESS-role profiles grouped by [Profile.status].
  final List<CategoryCount> businessPipeline;
}

/// A label paired with a count — every §2.7 admin breakdown that isn't a
/// time series (users by role, content volume by kind, business pipeline
/// by status) shares this shape.
class CategoryCount {
  const CategoryCount({required this.label, required this.count});

  final String label;
  final int count;
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

  /// §2.7's business dashboard, in full: applicant pipeline per listing,
  /// engagement rate on listings, candidate skill distribution across
  /// programmes, applicant demographics by programme and year, and the
  /// company profile's own reach. See migration 0013 for why every read
  /// here runs as the caller (invoker rights) rather than SECURITY
  /// DEFINER — §2.1's "business users may not access ... personal
  /// information beyond what a student has explicitly made visible" is
  /// enforced by RLS on `profiles`, and invoker rights is what keeps that
  /// enforced inside these aggregates instead of bypassing it.
  Future<BusinessStats> forBusiness(String userId) async {
    final results = await Future.wait<dynamic>([
      db.rpc('business_listing_pipeline'),
      db.rpc('business_applicant_skill_distribution', params: {'p_limit': 8}),
      db.rpc('business_applicant_demographics'),
      db
          .from('profile_analytics')
          .select('date, profile_views')
          .eq('user_id', userId)
          .order('date', ascending: false)
          .limit(30),
    ]);

    final pipeline = (results[0] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => ListingPipeline(
              title: (row['title'] ?? '') as String,
              status: (row['status'] ?? 'PENDING') as String,
              applicants: (row['applicant_count'] as num).toInt(),
              reach: (row['reach'] as num).toInt(),
            ))
        .toList();

    final skills = (results[1] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => CandidateSkill(
              skill: row['skill'] as String,
              count: (row['total'] as num).toInt(),
              topCourse: row['top_course'] as String?,
            ))
        .toList();

    final demographics = (results[2] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => CategoryCount(
              label: '${row['course']} · ${row['academic_year']}',
              count: (row['total'] as num).toInt(),
            ))
        .toList();

    final daily = (results[3] as List).cast<Map<String, dynamic>>();
    final profileViews = daily.fold<int>(
      0,
      (sum, row) => sum + ((row['profile_views'] as int?) ?? 0),
    );
    final viewsByDay = daily.reversed
        .map((row) => DailyMetric(
              date: DateTime.tryParse((row['date'] ?? '') as String) ??
                  DateTime.now(),
              value: (row['profile_views'] as int?) ?? 0,
            ))
        .toList();

    return BusinessStats(
      pipeline: pipeline,
      candidateSkills: skills,
      applicantDemographics: demographics,
      profileViews: profileViews,
      viewsByDay: viewsByDay,
    );
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

/// §2.7's business-dashboard return shape — see
/// [AnalyticsRepository.forBusiness].
class BusinessStats {
  const BusinessStats({
    required this.pipeline,
    required this.candidateSkills,
    required this.applicantDemographics,
    required this.profileViews,
    required this.viewsByDay,
  });

  /// One entry per posted listing (any status) — §2.7's "total applicant
  /// pipeline per posted opportunity" plus, per listing, what "engagement
  /// rate on job listings" is computed from.
  final List<ListingPipeline> pipeline;

  /// §2.7's "candidate skill distribution across Richfield programmes" —
  /// scoped to the caller's own applicants (see migration 0013's header
  /// for why), each skill paired with the programme it's most common in
  /// among those applicants.
  final List<CandidateSkill> candidateSkills;

  /// §2.7's "demographic breakdown of applicants by programme and year of
  /// study" — one [CategoryCount] per (course, academic year) combination,
  /// label already joined as "Course · Year".
  final List<CategoryCount> applicantDemographics;

  /// §2.7's "overall reach and visibility statistics for the company
  /// profile" — same `profile_analytics.profile_views` a student's
  /// dashboard reads, just for the business's own profile.
  final int profileViews;
  final List<DailyMetric> viewsByDay;
}

/// One posted listing's funnel: how many people it reached (distinct
/// viewers, see `opportunity_views` in migration 0013) versus how many of
/// them applied.
class ListingPipeline {
  const ListingPipeline({
    required this.title,
    required this.status,
    required this.applicants,
    required this.reach,
  });

  final String title;
  final String status;
  final int applicants;

  /// Distinct viewers. Always 0 for a PENDING/REJECTED listing — students
  /// only ever see ACTIVE ones — so this is never a listing's fault to
  /// display as a literal 0% engagement rate; the dashboard should read it
  /// as "not published yet" instead.
  final int reach;

  /// Applicants ÷ reach, as a 0–100 percentage. Null (not 0) when nobody
  /// has seen the listing yet, so the UI can tell "no engagement" apart
  /// from "no data to compute one".
  double? get engagementRate => reach == 0 ? null : (applicants / reach) * 100;
}

/// A skill among the caller's applicants, plus the programme it's most
/// common in — see `business_applicant_skill_distribution()` (migration
/// 0010) for how [topCourse] is picked.
class CandidateSkill {
  const CandidateSkill({
    required this.skill,
    required this.count,
    this.topCourse,
  });

  final String skill;
  final int count;
  final String? topCourse;
}
