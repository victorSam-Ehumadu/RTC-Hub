import '../core/supabase.dart';
import '../models/opportunity.dart';

/// Replaces `/api/opportunities` and `/api/events`.
class OpportunityRepository {
  const OpportunityRepository();

  static const _select = '''
    *,
    business:profiles!business_id(id, full_name, avatar_url, role, company_name, industry, company_location),
    opportunity_applications(count)
  ''';

  /// Live listings. `opps_select` already hides anything not ACTIVE unless the
  /// caller owns it or is an admin.
  Future<List<Opportunity>> browse({String? type}) async {
    var query = db.from('opportunities').select(_select).eq('status', 'ACTIVE');
    if (type != null) query = query.eq('type', type);

    final rows = await query.order('created_at', ascending: false);
    return _markApplied(rows.map(Opportunity.fromMap).toList());
  }

  /// Listings ranked against the student's skills, faculty and year.
  ///
  /// Replaces `services/matchingService.js`; the scoring now happens in the
  /// `matched_opportunities` SQL function so it runs next to the data.
  Future<List<Opportunity>> matched() async {
    final scores = await db.rpc('matched_opportunities') as List;
    if (scores.isEmpty) return [];

    final byId = {
      for (final s in scores)
        s['opportunity_id'] as String: (s['score'] as num?)?.toInt() ?? 0,
    };

    final rows = await db
        .from('opportunities')
        .select(_select)
        .inFilter('id', byId.keys.toList());

    final list = await _markApplied(rows.map(Opportunity.fromMap).toList());
    final ranked = [
      for (final o in list) o.withMatch(byId[o.id] ?? 0),
    ]..sort((a, b) => (b.matchScore ?? 0).compareTo(a.matchScore ?? 0));
    return ranked;
  }

  /// Listings posted by the signed-in business, including PENDING ones.
  Future<List<Opportunity>> mine() async {
    final rows = await db
        .from('opportunities')
        .select(_select)
        .eq('business_id', requireUserId)
        .order('created_at', ascending: false);
    return rows.map(Opportunity.fromMap).toList();
  }

  /// Creates a listing. It always lands as PENDING — `trg_opportunities_guard`
  /// overrides any status sent from here, so a business cannot publish
  /// straight to students.
  Future<Opportunity> create({
    required String title,
    required String description,
    required String type,
    String? location,
    bool remote = false,
    List<String> requiredSkills = const [],
    String? requiredFaculty,
    String? requiredYear,
    DateTime? expiresAt,
  }) async {
    final row = await db
        .from('opportunities')
        .insert({
          'business_id': requireUserId,
          'title': title.trim(),
          'description': description.trim(),
          'type': type,
          'location': location,
          'remote': remote,
          'required_skills': requiredSkills,
          'required_faculty': requiredFaculty,
          'required_year': requiredYear,
          'expires_at': expiresAt?.toIso8601String(),
        })
        .select(_select)
        .single();
    return Opportunity.fromMap(row);
  }

  Future<void> apply(String opportunityId, {String? coverNote}) =>
      db.from('opportunity_applications').insert({
        'opportunity_id': opportunityId,
        'applicant_id': requireUserId,
        'cover_note': coverNote,
      });

  /// Applications to one listing — readable by its owner and admins only.
  Future<List<Application>> applicationsFor(String opportunityId) async {
    final rows = await db
        .from('opportunity_applications')
        .select(
            '*, applicant:profiles!applicant_id(id, full_name, avatar_url, role, course, faculty, academic_year, cv_url, profile_completeness)')
        .eq('opportunity_id', opportunityId)
        .order('created_at', ascending: false);
    return rows.map(Application.fromMap).toList();
  }

  /// What the signed-in student has applied to.
  Future<List<Application>> myApplications() async {
    final rows = await db
        .from('opportunity_applications')
        .select('*, opportunity:opportunities!opportunity_id(*)')
        .eq('applicant_id', requireUserId)
        .order('created_at', ascending: false);
    return rows.map(Application.fromMap).toList();
  }

  Future<void> setApplicationStatus(String applicationId, String status) => db
      .from('opportunity_applications')
      .update({'status': status}).eq('id', applicationId);

  Future<List<Opportunity>> _markApplied(List<Opportunity> list) async {
    if (list.isEmpty) return list;
    final me = currentUserId;
    if (me == null) return list;

    final rows = await db
        .from('opportunity_applications')
        .select('opportunity_id')
        .eq('applicant_id', me)
        .inFilter('opportunity_id', list.map((o) => o.id).toList());

    final applied = {for (final r in rows) r['opportunity_id'] as String};
    return [
      for (final o in list)
        applied.contains(o.id)
            ? o.withMatch(o.matchScore ?? 0, applied: true)
            : o,
    ];
  }
}

/// Replaces `/api/events`.
class EventRepository {
  const EventRepository();

  Future<List<CampusEvent>> upcoming() async {
    final rows = await db
        .from('events')
        .select()
        .gte('event_date', DateTime.now().toIso8601String())
        .order('event_date');
    return rows.map(CampusEvent.fromMap).toList();
  }

  Future<List<CampusEvent>> past({int limit = 20}) async {
    final rows = await db
        .from('events')
        .select()
        .lt('event_date', DateTime.now().toIso8601String())
        .order('event_date', ascending: false)
        .limit(limit);
    return rows.map(CampusEvent.fromMap).toList();
  }

  /// Admin only — `events_all_admin` rejects anyone else.
  Future<void> create({
    required String title,
    required DateTime eventDate,
    String? description,
    String? location,
    String? virtualLink,
    List<String>? targetRoles,
  }) =>
      db.from('events').insert({
        'admin_id': requireUserId,
        'title': title.trim(),
        'event_date': eventDate.toIso8601String(),
        'description': description,
        'location': location,
        'virtual_link': virtualLink,
        'target_roles': targetRoles,
      });

  Future<void> remove(String id) => db.from('events').delete().eq('id', id);
}
