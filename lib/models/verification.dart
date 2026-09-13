/// An alumnus's claim to have graduated, plus the evidence for it (§2.1).
///
/// The claim is kept separate from the `profiles` row on purpose: these are
/// assertions under review, not facts about the account. Conflating them is
/// how an unverified claim ends up rendered on a profile as though it were a
/// credential — only [AlumniVerification] being APPROVED copies anything
/// across, and the database does that, not the client.
class AlumniVerification {
  const AlumniVerification({
    required this.id,
    required this.userId,
    required this.studentNumber,
    required this.graduationYear,
    required this.evidenceKind,
    required this.evidencePath,
    required this.status,
    required this.createdAt,
    this.course,
    this.campus,
    this.note,
    this.reviewerNote,
    this.fullName,
    this.email,
    this.avatarUrl,
  });

  final String id;
  final String userId;

  final String studentNumber;
  final int graduationYear;
  final String? course;
  final String? campus;

  /// GRADUATION_CERTIFICATE, ACADEMIC_TRANSCRIPT, STUDENT_CARD or OTHER.
  final String evidenceKind;

  /// A storage path, never a signed URL — a transcript link that outlives
  /// the review is a document leaking.
  final String evidencePath;

  /// PENDING, APPROVED or REJECTED.
  final String status;

  final DateTime createdAt;
  final String? note;

  /// Why it was turned down, shown to the applicant so a resubmission has
  /// some chance of being different.
  final String? reviewerNote;

  // Joined in by the review queue.
  final String? fullName;
  final String? email;
  final String? avatarUrl;

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  String get evidenceLabel => switch (evidenceKind) {
        'ACADEMIC_TRANSCRIPT' => 'Academic transcript',
        'STUDENT_CARD' => 'Student card',
        'OTHER' => 'Supporting document',
        _ => 'Graduation certificate',
      };

  factory AlumniVerification.fromMap(Map<String, dynamic> map) =>
      AlumniVerification(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        studentNumber: (map['claimed_student_number'] ?? '') as String,
        graduationYear:
            (map['claimed_graduation_year'] as num?)?.toInt() ?? 0,
        course: map['claimed_course'] as String?,
        campus: map['claimed_campus'] as String?,
        evidenceKind:
            (map['evidence_kind'] ?? 'GRADUATION_CERTIFICATE') as String,
        evidencePath: (map['evidence_path'] ?? '') as String,
        status: (map['status'] ?? 'PENDING') as String,
        createdAt:
            DateTime.tryParse((map['created_at'] ?? '') as String) ??
                DateTime.now(),
        note: map['note'] as String?,
        reviewerNote: map['reviewer_note'] as String?,
        fullName: map['full_name'] as String?,
        email: map['email'] as String?,
        avatarUrl: map['avatar_url'] as String?,
      );
}

/// The document types an alumnus can offer, in the order a reviewer would
/// most like to receive them.
const kEvidenceKinds = <({String value, String label, String hint})>[
  (
    value: 'GRADUATION_CERTIFICATE',
    label: 'Graduation certificate',
    hint: 'The certificate issued when you graduated.',
  ),
  (
    value: 'ACADEMIC_TRANSCRIPT',
    label: 'Academic transcript',
    hint: 'A final transcript showing your completed qualification.',
  ),
  (
    value: 'STUDENT_CARD',
    label: 'Student card',
    hint: 'Your old Richfield student card, if you still have it.',
  ),
  (
    value: 'OTHER',
    label: 'Something else',
    hint: 'Any official document that shows you studied here.',
  ),
];
