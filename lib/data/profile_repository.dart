import 'dart:async';

import '../core/supabase.dart';
import '../models/profile.dart';

/// Replaces `/api/profiles` and the skill/experience parts of the old
/// profile controller.
class ProfileRepository {
  const ProfileRepository();

  Future<Profile> byId(String userId) async {
    final row = await db.from('profiles').select().eq('id', userId).single();
    return Profile.fromMap(row);
  }

  /// Saves the editable subset of a profile. `role`, `status` and
  /// `profile_completeness` are rejected or recomputed by `trg_profiles_guard`,
  /// so [Profile.toUpdate] never includes them.
  Future<Profile> update(Profile profile) async {
    final row = await db
        .from('profiles')
        .update(profile.toUpdate())
        .eq('id', profile.id)
        .select()
        .single();
    return Profile.fromMap(row);
  }

  /// People search, used by the connections and messaging flows.
  ///
  /// Only ACTIVE profiles that have not hidden themselves are readable at all
  /// — `profiles_select` enforces that, so no extra filtering is needed here.
  Future<List<Profile>> search(String term, {String? role, int limit = 30}) async {
    final clean = term.trim();
    var query = db.from('profiles').select().neq('id', requireUserId);

    if (clean.isNotEmpty) {
      query = query.or(
        'full_name.ilike.%$clean%,'
        'course.ilike.%$clean%,'
        'company_name.ilike.%$clean%,'
        'bio.ilike.%$clean%',
      );
      unawaited(_logSkillSearch(clean));
    }
    if (role != null) query = query.eq('role', role);

    final rows = await query.order('profile_completeness', ascending: false).limit(limit);
    return rows.map(Profile.fromMap).toList();
  }

  /// Feeds the student dashboard's "most-searched skills" chart. Fire-and-
  /// forget like [recordView]: the RPC itself only counts the term when it
  /// matches a real skill, so this is safe to call on every search.
  Future<void> _logSkillSearch(String term) async {
    try {
      await db.rpc('log_skill_search', params: {'p_term': term});
    } catch (_) {
      // analytics only
    }
  }

  /// Alumni who studied the same course, for "Shadow-a-Senior".
  Future<List<Profile>> mentorsFor(Profile me, {int limit = 20}) async {
    var query = db.from('profiles').select().eq('role', 'ALUMNI');
    if (me.course != null) query = query.eq('course', me.course!);
    final rows = await query.limit(limit);
    return rows.map(Profile.fromMap).toList();
  }

  Future<int> logicPoints(String userId) async {
    final total = await db.rpc('total_logic_points', params: {'uid': userId});
    return (total as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> pointsLedger(String userId) async {
    final rows = await db
        .from('logic_points')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows;
  }

  /// Bumps today's view counter for someone else's profile. Fire-and-forget:
  /// a failure here should never block rendering the profile.
  Future<void> recordView(String userId) async {
    try {
      await db.rpc('record_profile_view', params: {'target': userId});
    } catch (_) {
      // analytics only
    }
  }

  // ─── Skills ────────────────────────────────────────────────

  Future<List<Skill>> skills(String userId) async {
    final rows = await db
        .from('skills')
        .select('*, skill_endorsements(count)')
        .eq('user_id', userId)
        .order('verified', ascending: false);
    return rows.map(Skill.fromMap).toList();
  }

  Future<void> addSkill(String name, {String? moduleRef}) => db.from('skills').insert({
        'user_id': requireUserId,
        'name': name.trim(),
        'module_ref': moduleRef,
      });

  Future<void> removeSkill(String skillId) =>
      db.from('skills').delete().eq('id', skillId);

  Future<void> endorse(String skillId, {String? note}) =>
      db.from('skill_endorsements').insert({
        'skill_id': skillId,
        'endorser_id': requireUserId,
        'note': note,
      });

  // ─── Work experience ───────────────────────────────────────

  Future<List<WorkExperience>> experience(String userId) async {
    final rows = await db
        .from('work_experience')
        .select()
        .eq('user_id', userId)
        .order('start_date', ascending: false);
    return rows.map(WorkExperience.fromMap).toList();
  }

  Future<void> addExperience({
    required String title,
    required String company,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
  }) =>
      db.from('work_experience').insert({
        'user_id': requireUserId,
        'title': title.trim(),
        'company': company.trim(),
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'description': description,
      });

  Future<void> removeExperience(String id) =>
      db.from('work_experience').delete().eq('id', id);

  // ─── Leaderboard ───────────────────────────────────────────

  // `leaderboard` (the view) is no longer directly readable by clients as
  // of migration 0016 — it stayed owner-rights so the points SUM is still
  // correct, but that meant it also ignored visibility_peers, so a user who
  // hid their profile still showed up here by name. leaderboard_rows()
  // applies that visibility check itself.
  Future<List<LeaderboardEntry>> leaderboard({int limit = 25}) async {
    final rows =
        await db.rpc('leaderboard_rows', params: {'p_limit': limit}) as List;
    return rows
        .map((r) => LeaderboardEntry.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
