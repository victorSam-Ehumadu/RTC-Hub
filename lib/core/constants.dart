/// Richfield's faculties and their courses, used by signup and profile editing.
class Faculty {
  const Faculty(this.code, this.name, this.courses);

  final String code;
  final String name;
  final List<String> courses;
}

const kFaculties = <Faculty>[
  Faculty('IT', 'Information Technology', [
    'BSc IT (Bachelor of Science in Information Technology)',
    'DIT (Diploma in Information Technology)',
    'HCIT (Higher Certificate in Information Technology)',
    'HCCF (Higher Certificate in Computer Forensics)',
  ]),
  Faculty('BUSINESS', 'Business and Management Sciences', [
    'BCom (Bachelor of Commerce)',
    'BCom AGA (Associate General Accountant)',
    'BCom AGA-IT',
    'BBA (Bachelor of Business Administration)',
    'DBA (Diploma in Business Administration)',
    'BPM (Bachelor of Public Management)',
    'DLGM (Diploma in Local Government Management)',
    'HCBA (Higher Certificate in Business Administration)',
    'HCOA (Higher Certificate in Office Administration)',
    'HCLGM (Higher Certificate in Local Government Management)',
    'RPLA (Recognition of Prior Learning Activities)',
  ]),
];

List<String> coursesForFaculty(String? code) =>
    kFaculties.where((f) => f.code == code).expand((f) => f.courses).toList();

/// Roles a person can pick at signup. ADMIN is deliberately absent — the
/// signup trigger rejects it.
const kSignupRoles = <String>['STUDENT', 'ALUMNI', 'BUSINESS'];

const kAcademicYears = <String>['1st Year', '2nd Year', '3rd Year', 'Alumni'];

/// Campuses a student/alumnus may have attended, used by signup and profile
/// editing (guidelines §2.3 mandates "Campus attended" on every profile).
const kCampuses = <String>[
  'Bryanston Campus',
  'Cape Town Campus',
  'Centurion Campus',
  'Musgrave Campus',
  'Newtown Junction Campus',
  'Polokwane Campus',
  'Pretoria Campus',
  'Umhlanga Campus',
];

/// A descending list of years for the enrollment/graduation-year dropdowns,
/// spanning [before] years in the past to [after] in the future from now —
/// enrollment is almost always in the past, but an expected graduation year
/// for a current student is usually a few years out.
List<int> kYearOptions({int before = 20, int after = 6}) {
  final year = DateTime.now().year;
  return [for (var y = year + after; y >= year - before; y--) y];
}

const kOpportunityTypes = <String>[
  'INTERNSHIP',
  'LEARNERSHIP',
  'PART_TIME',
  'GRADUATE',
];

/// Languages offered when attaching a snippet to a post.
const kCodeLanguages = <String>[
  'dart',
  'java',
  'python',
  'javascript',
  'typescript',
  'sql',
  'csharp',
  'cpp',
  'php',
  'html',
  'css',
];

const kReactionEmojis = <String>['👍', '🔥', '🧠', '🎯', '👏'];

/// Domains accepted for student/alumni registration: Richfield's own, plus
/// the AAA partner-campus domains. Kept as a list so a further domain is a
/// one-line addition here and in `handle_new_user()`. Also the single
/// source of truth for the signup email domain dropdown.
const kStudentEmailDomains = <String>[
  'my.richfield.ac.za',
  'richfield.ac.za',
  'my.aaa.ac.za',
  'aaa.ac.za',
];

/// Student emails must sit on one of [kStudentEmailDomains] with a 9-digit
/// prefix. The same rule is enforced in `handle_new_user()`; this copy exists
/// so the user gets a useful message before the network round-trip.
bool isValidStudentEmail(String email) {
  final clean = email.trim().toLowerCase();
  final onDomain =
      kStudentEmailDomains.any((domain) => clean.endsWith('@$domain'));
  if (!onDomain) return false;
  final prefix = clean.split('@').first;
  return RegExp(r'^\d{9}$').hasMatch(prefix);
}

/// Checks a *new* password against the strength policy used at signup and
/// when changing a password. Returns null when it passes, otherwise a
/// message naming the first unmet requirement. Pure (no BuildContext) so a
/// [TextFormField.validator] can call it directly.
///
/// Does not apply to a password being verified rather than created (e.g. a
/// "current password" re-auth field) — those only need a non-empty check.
final _passwordSpecialChars = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]/\\~`]');

String? passwordPolicyError(String password) {
  if (password.length < 8) return 'Use at least 8 characters.';
  if (!password.contains(RegExp('[A-Z]'))) {
    return 'Include at least one uppercase letter.';
  }
  if (!password.contains(RegExp('[a-z]'))) {
    return 'Include at least one lowercase letter.';
  }
  if (!password.contains(RegExp('[0-9]'))) {
    return 'Include at least one number.';
  }
  if (!password.contains(_passwordSpecialChars)) {
    return 'Include at least one special character.';
  }
  return null;
}
