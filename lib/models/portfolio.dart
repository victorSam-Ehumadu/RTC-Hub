/// The §2.3 portfolio records that live in their own tables.
///
/// All four share a shape — a title, an optional organisation, an optional
/// link, an optional date — but they are kept as separate Dart types rather
/// than one generic `Entry` because the screens ask different questions of
/// them and a single type would mean every widget re-deriving which fields
/// are meaningful.
library;

/// A GitHub repository or a deployed application (§2.3).
class PortfolioItem {
  const PortfolioItem({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.url,
    this.description,
    this.tech = const [],
  });

  final String id;
  final String userId;

  /// 'REPO' or 'LIVE_APP'.
  final String kind;

  final String title;
  final String url;
  final String? description;
  final List<String> tech;

  bool get isRepo => kind == 'REPO';

  factory PortfolioItem.fromMap(Map<String, dynamic> map) => PortfolioItem(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        kind: (map['kind'] ?? 'REPO') as String,
        title: (map['title'] ?? '') as String,
        url: (map['url'] ?? '') as String,
        description: map['description'] as String?,
        tech: map['tech'] is List
            ? (map['tech'] as List).map((t) => '$t').toList()
            : const [],
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'kind': kind,
        'title': title.trim(),
        'url': url.trim(),
        'description': description,
        'tech': tech.isEmpty ? null : tech,
      };
}

/// A digital badge or a professional certification (§2.3).
class Credential {
  const Credential({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    this.issuer,
    this.issuedOn,
    this.expiresOn,
    this.url,
  });

  final String id;
  final String userId;

  /// 'BADGE' or 'CERTIFICATION'.
  final String kind;

  final String title;
  final String? issuer;
  final DateTime? issuedOn;
  final DateTime? expiresOn;
  final String? url;

  bool get isBadge => kind == 'BADGE';

  /// A certification that has lapsed is still worth showing, but not worth
  /// showing as though it were current.
  bool get hasExpired =>
      expiresOn != null && expiresOn!.isBefore(DateTime.now());

  factory Credential.fromMap(Map<String, dynamic> map) => Credential(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        kind: (map['kind'] ?? 'CERTIFICATION') as String,
        title: (map['title'] ?? '') as String,
        issuer: map['issuer'] as String?,
        issuedOn: DateTime.tryParse((map['issued_on'] ?? '') as String),
        expiresOn: DateTime.tryParse((map['expires_on'] ?? '') as String),
        url: map['url'] as String?,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'kind': kind,
        'title': title.trim(),
        'issuer': issuer,
        'issued_on': issuedOn?.toIso8601String(),
        'expires_on': expiresOn?.toIso8601String(),
        'url': url,
      };
}

/// An academic achievement, a leadership role, or a club/society/hackathon
/// entry (§2.3). One type, three `kind`s, because the fields are identical
/// and only the heading differs.
class ProfileHighlight {
  const ProfileHighlight({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    this.organisation,
    this.description,
    this.startedOn,
    this.endedOn,
    this.url,
  });

  final String id;
  final String userId;

  /// 'ACHIEVEMENT', 'LEADERSHIP' or 'ACTIVITY'.
  final String kind;

  final String title;
  final String? organisation;
  final String? description;
  final DateTime? startedOn;
  final DateTime? endedOn;
  final String? url;

  factory ProfileHighlight.fromMap(Map<String, dynamic> map) =>
      ProfileHighlight(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        kind: (map['kind'] ?? 'ACHIEVEMENT') as String,
        title: (map['title'] ?? '') as String,
        organisation: map['organisation'] as String?,
        description: map['description'] as String?,
        startedOn: DateTime.tryParse((map['started_on'] ?? '') as String),
        endedOn: DateTime.tryParse((map['ended_on'] ?? '') as String),
        url: map['url'] as String?,
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        'kind': kind,
        'title': title.trim(),
        'organisation': organisation,
        'description': description,
        'started_on': startedOn?.toIso8601String(),
        'ended_on': endedOn?.toIso8601String(),
        'url': url,
      };

  static String headingFor(String kind) => switch (kind) {
        'LEADERSHIP' => 'Leadership',
        'ACTIVITY' => 'Clubs and activities',
        _ => 'Achievements and awards',
      };
}

/// One alumnus on the career pathway explorer (§2.5).
class CareerPathwayEntry {
  const CareerPathwayEntry({
    required this.id,
    required this.fullName,
    required this.roles,
    this.avatarUrl,
    this.course,
    this.graduationYear,
    this.headline,
    this.fieldOfWork,
  });

  final String id;
  final String fullName;
  final String? avatarUrl;
  final String? course;
  final int? graduationYear;
  final String? headline;
  final String? fieldOfWork;

  /// Newest first, which is how a trajectory reads: where they are now, then
  /// how they got there.
  final List<PathwayRole> roles;

  /// What a student actually wants off this card at a glance.
  String? get currentRole => roles.isEmpty ? null : roles.first.label;

  factory CareerPathwayEntry.fromMap(Map<String, dynamic> map) =>
      CareerPathwayEntry(
        id: map['id'] as String,
        fullName: (map['full_name'] ?? '') as String,
        avatarUrl: map['avatar_url'] as String?,
        course: map['course'] as String?,
        graduationYear: (map['graduation_year'] as num?)?.toInt(),
        headline: map['headline'] as String?,
        fieldOfWork: map['field_of_work'] as String?,
        roles: map['roles'] is List
            ? (map['roles'] as List)
                .whereType<Map>()
                .map((r) => PathwayRole.fromMap(Map<String, dynamic>.from(r)))
                .toList()
            : const [],
      );
}

class PathwayRole {
  const PathwayRole({
    required this.title,
    required this.company,
    this.startDate,
    this.endDate,
    this.kind = 'EMPLOYMENT',
  });

  final String title;
  final String company;
  final DateTime? startDate;
  final DateTime? endDate;
  final String kind;

  bool get isVenture => kind == 'VENTURE';
  bool get isCurrent => endDate == null;

  String get label => '$title at $company';

  String get period {
    final from = startDate?.year;
    final to = endDate?.year;
    if (from == null && to == null) return '';
    if (to == null) return '$from — now';
    return from == to ? '$to' : '$from — $to';
  }

  factory PathwayRole.fromMap(Map<String, dynamic> map) => PathwayRole(
        title: (map['title'] ?? '') as String,
        company: (map['company'] ?? '') as String,
        startDate: DateTime.tryParse((map['start_date'] ?? '') as String),
        endDate: DateTime.tryParse((map['end_date'] ?? '') as String),
        kind: (map['kind'] ?? 'EMPLOYMENT') as String,
      );
}
