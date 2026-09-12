/// One labelled point on a chart.
///
/// Every dashboard query in migration 0012 returns `{label, value}` pairs so
/// the screens share one shape and one set of chart widgets. Without that,
/// three dashboards means three bespoke parsers and three ways for a chart to
/// be subtly wrong.
class DataPoint {
  const DataPoint({required this.label, required this.value});

  final String label;
  final num value;

  /// Dates arrive as `YYYY-MM-DD`; axes want `14 Sep`.
  String get shortDate {
    final parsed = DateTime.tryParse(label);
    if (parsed == null) return label;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${parsed.day} ${months[parsed.month - 1]}';
  }

  factory DataPoint.fromMap(Map<String, dynamic> map) => DataPoint(
        label: '${map['label'] ?? ''}',
        value: (map['value'] as num?) ?? 0,
      );

  static List<DataPoint> listFrom(Object? raw) => raw is List
      ? [
          for (final item in raw)
            if (item is Map) DataPoint.fromMap(Map<String, dynamic>.from(item)),
        ]
      : const [];
}

/// A row of the business applicant pipeline — one posted listing.
class PipelineRow {
  const PipelineRow({
    required this.opportunityId,
    required this.title,
    required this.status,
    required this.applicants,
    required this.shortlisted,
    required this.rejected,
    this.postedAt,
  });

  final String opportunityId;
  final String title;
  final String status;
  final int applicants;
  final int shortlisted;
  final int rejected;
  final DateTime? postedAt;

  /// Still waiting on a decision — the number the recruiter has to act on.
  int get pending => (applicants - shortlisted - rejected).clamp(0, applicants);

  factory PipelineRow.fromMap(Map<String, dynamic> map) => PipelineRow(
        opportunityId: map['opportunity_id'] as String,
        title: (map['title'] ?? '') as String,
        status: (map['status'] ?? 'PENDING') as String,
        applicants: (map['applicants'] as num?)?.toInt() ?? 0,
        shortlisted: (map['shortlisted'] as num?)?.toInt() ?? 0,
        rejected: (map['rejected'] as num?)?.toInt() ?? 0,
        postedAt: DateTime.tryParse((map['posted_at'] ?? '') as String),
      );
}

/// Everything the business dashboard plots (§2.7).
class BusinessAnalytics {
  const BusinessAnalytics({
    required this.pipeline,
    required this.byProgramme,
    required this.byYear,
    required this.byFaculty,
    required this.topSkills,
    required this.applicationsByDay,
    required this.profileViewsByDay,
    required this.totalApplicants,
    required this.activeListings,
    required this.pendingListings,
    required this.applicationsPerListing,
  });

  final List<PipelineRow> pipeline;
  final List<DataPoint> byProgramme;
  final List<DataPoint> byYear;
  final List<DataPoint> byFaculty;
  final List<DataPoint> topSkills;
  final List<DataPoint> applicationsByDay;
  final List<DataPoint> profileViewsByDay;
  final int totalApplicants;
  final int activeListings;
  final int pendingListings;
  final double applicationsPerListing;

  bool get isEmpty => pipeline.isEmpty && totalApplicants == 0;
}

/// Everything the administrator dashboard plots (§2.7).
class AdminAnalytics {
  const AdminAnalytics({
    required this.usersByType,
    required this.usersByStatus,
    required this.registrationsByDay,
    required this.contentByDay,
    required this.contentVolume,
    required this.monthlyActiveUsers,
    required this.flaggedOpen,
    required this.flaggedResolved,
    required this.businessPipeline,
    required this.opportunityPipeline,
  });

  final List<DataPoint> usersByType;
  final List<DataPoint> usersByStatus;
  final List<DataPoint> registrationsByDay;
  final List<DataPoint> contentByDay;
  final Map<String, int> contentVolume;
  final int monthlyActiveUsers;
  final int flaggedOpen;
  final int flaggedResolved;
  final Map<String, int> businessPipeline;
  final Map<String, int> opportunityPipeline;

  int get totalUsers =>
      usersByType.fold<int>(0, (sum, p) => sum + p.value.toInt());

  static Map<String, int> _counts(Object? raw) => raw is Map
      ? {
          for (final e in raw.entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        }
      : const {};

  factory AdminAnalytics.fromMap(Map<String, dynamic> map) => AdminAnalytics(
        usersByType: DataPoint.listFrom(map['users_by_type']),
        usersByStatus: DataPoint.listFrom(map['users_by_status']),
        registrationsByDay: DataPoint.listFrom(map['registrations_by_day']),
        contentByDay: DataPoint.listFrom(map['content_by_day']),
        contentVolume: _counts(map['content_volume']),
        monthlyActiveUsers: (map['monthly_active_users'] as num?)?.toInt() ?? 0,
        flaggedOpen: (map['flagged_open'] as num?)?.toInt() ?? 0,
        flaggedResolved: (map['flagged_resolved'] as num?)?.toInt() ?? 0,
        businessPipeline: _counts(map['business_pipeline']),
        opportunityPipeline: _counts(map['opportunity_pipeline']),
      );
}
