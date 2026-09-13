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

/// Richfield campuses, for the profile's "campus attended" field
/// (§2.3). A list rather than an enum in the database: campuses open,
/// close and get renamed, and none of that should need a migration.
const kCampuses = <String>[
  'Johannesburg (Braamfontein)',
  'Johannesburg (Randburg)',
  'Pretoria',
  'Durban (Umhlanga)',
  'Durban (Central)',
  'Pietermaritzburg',
  'Cape Town',
  'Port Elizabeth',
  'East London',
  'Polokwane',
  'Nelspruit',
  'Online / Distance',
];

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

/// Campus domains a student may register from. §2.1 requires the AAA domains
/// alongside Richfield's. Kept in sync with `handle_new_user()` in migration
/// `0006_fix_client_access.sql` — change both or neither.
const kStudentEmailDomains = <String>[
  '@my.richfield.ac.za',
  '@richfield.ac.za',
  '@my.aaa.ac.za',
  '@aaa.ac.za',
];

/// Student emails must sit on a campus domain with a 9-digit prefix. The same
/// rule is enforced in `handle_new_user()`; this copy exists so the user gets
/// a useful message before the network round-trip.
bool isValidStudentEmail(String email) {
  final clean = email.trim().toLowerCase();
  if (!kStudentEmailDomains.any(clean.endsWith)) return false;
  final prefix = clean.split('@').first;
  return RegExp(r'^\d{9}$').hasMatch(prefix);
}
