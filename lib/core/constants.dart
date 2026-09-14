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

/// The domains a student may register on, per the hackathon guidelines
/// (§2.1): Richfield's own domains plus the AAA partner-campus domains. This
/// is the single source of truth for both the signup email dropdown and
/// [isValidStudentEmail] below — the same four domains must also be enforced
/// server-side in `handle_new_user()`, since this client copy is only a
/// convenience, not the actual boundary (see CLAUDE.md's security model).
const kStudentEmailDomains = <String>[
  'my.richfield.ac.za',
  'richfield.ac.za',
  'my.aaa.ac.za',
  'aaa.ac.za',
];

/// Student emails must sit on one of [kStudentEmailDomains] with a 9-digit
/// prefix. The same rule is enforced in `handle_new_user()`; this copy
/// exists so the user gets a useful message before the network round-trip.
bool isValidStudentEmail(String email) {
  final clean = email.trim().toLowerCase();
  final onDomain = kStudentEmailDomains.any((d) => clean.endsWith('@$d'));
  if (!onDomain) return false;
  final prefix = clean.split('@').first;
  return RegExp(r'^\d{9}$').hasMatch(prefix);
}
