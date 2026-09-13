import '../core/supabase.dart';
import '../models/portfolio.dart';

/// The §2.3 portfolio sections, plus §2.5's career pathway explorer.
///
/// Separate from ProfileRepository because these are child collections a
/// user adds to and removes from, not fields on a row — and because the
/// pathway explorer is a query about *other people's* careers that happens
/// to hang off the same schema.
class PortfolioRepository {
  const PortfolioRepository();

  // ─── Projects and deployed apps ────────────────────────────

  Future<List<PortfolioItem>> items(String userId, {String? kind}) async {
    var query =
        db.from('portfolio_items').select().eq('user_id', userId);
    if (kind != null) query = query.eq('kind', kind);

    final rows = await query.order('created_at', ascending: false);
    return rows.map(PortfolioItem.fromMap).toList();
  }

  Future<void> addItem(PortfolioItem item) =>
      db.from('portfolio_items').insert(item.toInsert(requireUserId));

  Future<void> removeItem(String id) =>
      db.from('portfolio_items').delete().eq('id', id);

  // ─── Badges and certifications ─────────────────────────────

  Future<List<Credential>> credentials(String userId, {String? kind}) async {
    var query = db.from('credentials').select().eq('user_id', userId);
    if (kind != null) query = query.eq('kind', kind);

    // Nulls last: an undated certification is not necessarily the oldest,
    // it is just one nobody typed a date for.
    final rows =
        await query.order('issued_on', ascending: false, nullsFirst: false);
    return rows.map(Credential.fromMap).toList();
  }

  Future<void> addCredential(Credential credential) =>
      db.from('credentials').insert(credential.toInsert(requireUserId));

  Future<void> removeCredential(String id) =>
      db.from('credentials').delete().eq('id', id);

  // ─── Achievements, leadership, activities ──────────────────

  Future<List<ProfileHighlight>> highlights(
    String userId, {
    String? kind,
  }) async {
    var query = db.from('profile_highlights').select().eq('user_id', userId);
    if (kind != null) query = query.eq('kind', kind);

    final rows =
        await query.order('started_on', ascending: false, nullsFirst: false);
    return rows.map(ProfileHighlight.fromMap).toList();
  }

  Future<void> addHighlight(ProfileHighlight highlight) =>
      db.from('profile_highlights').insert(highlight.toInsert(requireUserId));

  Future<void> removeHighlight(String id) =>
      db.from('profile_highlights').delete().eq('id', id);

  // ─── Career pathway explorer (§2.5) ────────────────────────

  /// Alumni who studied [course], with the roles they have held.
  ///
  /// Null [course] means the caller's own programme, which is the question
  /// the screen opens with: "where do people from my course end up".
  Future<List<CareerPathwayEntry>> pathway({String? course}) async {
    final rows = await db.rpc('career_pathway', params: {'p_course': course})
        as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(CareerPathwayEntry.fromMap)
        .toList();
  }

  /// Programmes that actually have alumni, for the picker — offering a
  /// course with nobody behind it is a dead end dressed as a filter.
  Future<List<({String course, int alumni})>> pathwayCourses() async {
    final rows = await db.rpc('career_pathway_courses') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        (
          course: (row['course'] ?? '') as String,
          alumni: (row['alumni'] as num?)?.toInt() ?? 0,
        ),
    ];
  }
}
