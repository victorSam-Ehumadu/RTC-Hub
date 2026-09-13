import 'profile.dart';

/// A row from `opportunities`. New listings are forced to `PENDING` by
/// `trg_opportunities_guard`; only an admin can flip one to `ACTIVE`.
class Opportunity {
  const Opportunity({
    required this.id,
    required this.businessId,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.createdAt,
    this.business,
    this.location,
    this.remote = false,
    this.requiredSkills = const [],
    this.requiredFaculty,
    this.requiredYear,
    this.expiresAt,
    this.applicationCount = 0,
    this.hasApplied = false,
    this.matchScore,
  });

  final String id;
  final String businessId;
  final String title;
  final String description;
  final String type;
  final String status;
  final DateTime createdAt;
  final Profile? business;
  final String? location;
  final bool remote;
  final List<String> requiredSkills;
  final String? requiredFaculty;
  final String? requiredYear;
  final DateTime? expiresAt;
  final int applicationCount;
  final bool hasApplied;

  /// Set from the `matched_opportunities` RPC when browsing the matched tab.
  final int? matchScore;

  bool get isActive => status == 'ACTIVE';
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  String get typeLabel => switch (type) {
        'PART_TIME' => 'Part-time',
        'INTERNSHIP' => 'Internship',
        'LEARNERSHIP' => 'Learnership',
        'GRADUATE' => 'Graduate',
        _ => type,
      };

  String get whereLabel {
    if (remote) return location == null ? 'Remote' : 'Remote · $location';
    return location ?? 'On site';
  }

  factory Opportunity.fromMap(Map<String, dynamic> map) => Opportunity(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        title: (map['title'] ?? '') as String,
        description: (map['description'] ?? '') as String,
        type: (map['type'] ?? 'INTERNSHIP') as String,
        status: (map['status'] ?? 'PENDING') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ?? DateTime.now(),
        business: map['business'] is Map<String, dynamic>
            ? Profile.fromMap(map['business'] as Map<String, dynamic>)
            : null,
        location: map['location'] as String?,
        remote: (map['remote'] as bool?) ?? false,
        requiredSkills: (map['required_skills'] as List?)?.cast<String>() ?? const [],
        requiredFaculty: map['required_faculty'] as String?,
        requiredYear: map['required_year'] as String?,
        expiresAt: DateTime.tryParse((map['expires_at'] ?? '') as String),
        applicationCount: embeddedCount(map['opportunity_applications']),
      );

  Opportunity withMatch(int score, {bool? applied}) => Opportunity(
        id: id,
        businessId: businessId,
        title: title,
        description: description,
        type: type,
        status: status,
        createdAt: createdAt,
        business: business,
        location: location,
        remote: remote,
        requiredSkills: requiredSkills,
        requiredFaculty: requiredFaculty,
        requiredYear: requiredYear,
        expiresAt: expiresAt,
        applicationCount: applicationCount,
        hasApplied: applied ?? hasApplied,
        matchScore: score,
      );
}

/// A row from `opportunity_applications`.
class Application {
  const Application({
    required this.id,
    required this.opportunityId,
    required this.applicantId,
    required this.status,
    required this.createdAt,
    this.applicant,
    this.opportunity,
    this.coverNote,
  });

  final String id;
  final String opportunityId;
  final String applicantId;
  final String status;
  final DateTime createdAt;
  final Profile? applicant;
  final Opportunity? opportunity;
  final String? coverNote;

  factory Application.fromMap(Map<String, dynamic> map) => Application(
        id: map['id'] as String,
        opportunityId: map['opportunity_id'] as String,
        applicantId: map['applicant_id'] as String,
        status: (map['status'] ?? 'APPLIED') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ?? DateTime.now(),
        applicant: map['applicant'] is Map<String, dynamic>
            ? Profile.fromMap(map['applicant'] as Map<String, dynamic>)
            : null,
        opportunity: map['opportunity'] is Map<String, dynamic>
            ? Opportunity.fromMap(map['opportunity'] as Map<String, dynamic>)
            : null,
        coverNote: map['cover_note'] as String?,
      );
}

/// A row from `events`.
class CampusEvent {
  const CampusEvent({
    required this.id,
    required this.title,
    required this.eventDate,
    this.description,
    this.location,
    this.virtualLink,
    this.targetRoles = const [],
    this.faculty,
  });

  final String id;
  final String title;
  final DateTime eventDate;
  final String? description;
  final String? location;
  final String? virtualLink;
  final List<String> targetRoles;

  /// Which faculty this event is for. Null reaches both — added by
  /// migration 0007, which also made events_select honour it.
  final String? faculty;

  bool get isPast => eventDate.isBefore(DateTime.now());
  bool get isVirtual => virtualLink != null && virtualLink!.isNotEmpty;

  factory CampusEvent.fromMap(Map<String, dynamic> map) => CampusEvent(
        id: map['id'] as String,
        title: (map['title'] ?? '') as String,
        eventDate:
            DateTime.tryParse((map['event_date'] ?? '') as String) ?? DateTime.now(),
        description: map['description'] as String?,
        location: map['location'] as String?,
        virtualLink: map['virtual_link'] as String?,
        targetRoles: (map['target_roles'] as List?)?.cast<String>() ?? const [],
        faculty: map['faculty'] as String?,
      );
}
