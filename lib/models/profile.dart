/// A row from `profiles`, which extends Supabase's `auth.users`.
///
/// Note that `role` and `status` are read-only from the app's point of view:
/// the `trg_profiles_guard` trigger rejects any non-admin attempt to change
/// them, so [toUpdate] never sends them.
class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.studentNumber,
    this.avatarUrl,
    this.bio,
    this.faculty,
    this.course,
    this.academicYear,
    this.graduationYear,
    this.companyName,
    this.industry,
    this.companyLocation,
    this.talentDescription,
    this.cvUrl,
    this.portfolioUrl,
    this.profileCompleteness = 0,
    this.visibilityBusiness = true,
    this.visibilityPeers = true,
    this.contentInterests = const [],
    this.createdAt,
  });

  final String id;
  final String email;
  final String fullName;
  final String role;
  final String status;
  final String? studentNumber;
  final String? avatarUrl;
  final String? bio;
  final String? faculty;
  final String? course;
  final String? academicYear;
  final int? graduationYear;
  final String? companyName;
  final String? industry;
  final String? companyLocation;
  final String? talentDescription;
  final String? cvUrl;
  final String? portfolioUrl;
  final int profileCompleteness;
  final bool visibilityBusiness;
  final bool visibilityPeers;

  /// Which faculties' content this account sees. Students and alumni get
  /// their own faculty; a business picks one or both at signup. Kept in step
  /// by `trg_profiles_interests` — see migration 0007.
  final List<String> contentInterests;

  final DateTime? createdAt;

  bool get isStudent => role == 'STUDENT';
  bool get isAlumni => role == 'ALUMNI';
  bool get isBusiness => role == 'BUSINESS';
  bool get isAdmin => role == 'ADMIN';
  bool get isActive => status == 'ACTIVE';
  bool get isPending => status == 'PENDING';

  bool get isIt => faculty == 'IT';
  bool get isBusinessFaculty => faculty == 'BUSINESS';

  /// True when this account sees content from both faculties — every admin,
  /// and a business that recruits from both.
  bool get seesBothFaculties => contentInterests.length > 1;

  /// What a composer should attach to a new post. Null for an account that
  /// spans both faculties, which is what makes a post cross-faculty.
  String? get postingFaculty {
    if (faculty != null) return faculty;
    return contentInterests.length == 1 ? contentInterests.first : null;
  }

  /// Businesses are shown by company; everyone else by their own name.
  String get displayName =>
      isBusiness && (companyName?.isNotEmpty ?? false) ? companyName! : fullName;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  /// Line under the name: course for students, industry for businesses.
  String get subtitle {
    if (isBusiness) return industry ?? 'Business';
    final bits = [course, academicYear].where((b) => b != null && b.isNotEmpty);
    return bits.isEmpty ? role : bits.join(' · ');
  }

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        email: (map['email'] ?? '') as String,
        fullName: (map['full_name'] ?? '') as String,
        role: (map['role'] ?? 'STUDENT') as String,
        status: (map['status'] ?? 'PENDING') as String,
        studentNumber: map['student_number'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        bio: map['bio'] as String?,
        faculty: map['faculty'] as String?,
        course: map['course'] as String?,
        academicYear: map['academic_year'] as String?,
        graduationYear: map['graduation_year'] as int?,
        companyName: map['company_name'] as String?,
        industry: map['industry'] as String?,
        companyLocation: map['company_location'] as String?,
        talentDescription: map['talent_description'] as String?,
        cvUrl: map['cv_url'] as String?,
        portfolioUrl: map['portfolio_url'] as String?,
        profileCompleteness: (map['profile_completeness'] as int?) ?? 0,
        visibilityBusiness: (map['visibility_business'] as bool?) ?? true,
        visibilityPeers: (map['visibility_peers'] as bool?) ?? true,
        contentInterests: map['content_interests'] is List
            ? (map['content_interests'] as List).cast<String>()
            : const [],
        createdAt: DateTime.tryParse((map['created_at'] ?? '') as String),
      );

  /// Only the fields a user is allowed to edit about themselves.
  Map<String, dynamic> toUpdate() => {
        'full_name': fullName,
        'bio': bio,
        'avatar_url': avatarUrl,
        'faculty': faculty,
        'course': course,
        'academic_year': academicYear,
        'graduation_year': graduationYear,
        'company_name': companyName,
        'industry': industry,
        'company_location': companyLocation,
        'talent_description': talentDescription,
        'cv_url': cvUrl,
        'portfolio_url': portfolioUrl,
        'visibility_business': visibilityBusiness,
        'visibility_peers': visibilityPeers,
        // Editable by a business choosing which cohorts to follow. The
        // trigger overwrites it for students and alumni, so sending it is
        // harmless there.
        'content_interests': contentInterests.isEmpty ? null : contentInterests,
      };

  Profile copyWith({
    String? fullName,
    String? avatarUrl,
    String? bio,
    String? faculty,
    String? course,
    String? academicYear,
    int? graduationYear,
    String? companyName,
    String? industry,
    String? companyLocation,
    String? talentDescription,
    String? cvUrl,
    String? portfolioUrl,
    bool? visibilityBusiness,
    bool? visibilityPeers,
    List<String>? contentInterests,
  }) =>
      Profile(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        role: role,
        status: status,
        studentNumber: studentNumber,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        faculty: faculty ?? this.faculty,
        course: course ?? this.course,
        academicYear: academicYear ?? this.academicYear,
        graduationYear: graduationYear ?? this.graduationYear,
        companyName: companyName ?? this.companyName,
        industry: industry ?? this.industry,
        companyLocation: companyLocation ?? this.companyLocation,
        talentDescription: talentDescription ?? this.talentDescription,
        cvUrl: cvUrl ?? this.cvUrl,
        portfolioUrl: portfolioUrl ?? this.portfolioUrl,
        profileCompleteness: profileCompleteness,
        visibilityBusiness: visibilityBusiness ?? this.visibilityBusiness,
        visibilityPeers: visibilityPeers ?? this.visibilityPeers,
        contentInterests: contentInterests ?? this.contentInterests,
        createdAt: createdAt,
      );
}

/// A `skills` row plus its endorsement count.
class Skill {
  const Skill({
    required this.id,
    required this.userId,
    required this.name,
    this.verified = false,
    this.moduleRef,
    this.endorsements = 0,
  });

  final String id;
  final String userId;
  final String name;
  final bool verified;
  final String? moduleRef;
  final int endorsements;

  factory Skill.fromMap(Map<String, dynamic> map) => Skill(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        name: (map['name'] ?? '') as String,
        verified: (map['verified'] as bool?) ?? false,
        moduleRef: map['module_ref'] as String?,
        endorsements: _embeddedCount(map['skill_endorsements']),
      );
}

/// A `work_experience` row.
class WorkExperience {
  const WorkExperience({
    required this.id,
    required this.userId,
    required this.title,
    required this.company,
    this.startDate,
    this.endDate,
    this.description,
  });

  final String id;
  final String userId;
  final String title;
  final String company;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? description;

  factory WorkExperience.fromMap(Map<String, dynamic> map) => WorkExperience(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        title: (map['title'] ?? '') as String,
        company: (map['company'] ?? '') as String,
        startDate: DateTime.tryParse((map['start_date'] ?? '') as String),
        endDate: DateTime.tryParse((map['end_date'] ?? '') as String),
        description: map['description'] as String?,
      );
}

/// A row from the `leaderboard` view.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.id,
    required this.fullName,
    required this.totalPoints,
    this.avatarUrl,
    this.course,
    this.skillCount = 0,
  });

  final String id;
  final String fullName;
  final int totalPoints;
  final String? avatarUrl;
  final String? course;
  final int skillCount;

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) => LeaderboardEntry(
        id: map['id'] as String,
        fullName: (map['full_name'] ?? '') as String,
        totalPoints: (map['total_points'] as num?)?.toInt() ?? 0,
        avatarUrl: map['avatar_url'] as String?,
        course: map['course'] as String?,
        skillCount: (map['skill_count'] as num?)?.toInt() ?? 0,
      );
}

/// PostgREST returns embedded aggregates as `[{"count": n}]`.
int _embeddedCount(dynamic value) {
  if (value is List && value.isNotEmpty) {
    final first = value.first;
    if (first is Map && first['count'] is num) {
      return (first['count'] as num).toInt();
    }
    return value.length;
  }
  return 0;
}

/// Shared by the other models in this package.
int embeddedCount(dynamic value) => _embeddedCount(value);
