/// Richfield's faculties and their courses, used by signup and profile editing.
class Faculty {
  const Faculty(this.code, this.name, this.courses);

  final String code;
  final String name;
  final List<String> courses;
}

const kFaculties = <Faculty>[
  Faculty('IT', 'Information Technology', [
    'BSc Information Technology',
    'Diploma in Information Technology',
    'Higher Certificate in Information Technology',
    'Higher Certificate in Computer Forensics',
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

/// Student emails must sit on a Richfield domain with a 9-digit prefix. The
/// same rule is enforced in `handle_new_user()`; this copy exists so the user
/// gets a useful message before the network round-trip.
bool isValidStudentEmail(String email) {
  final clean = email.trim().toLowerCase();
  final onDomain = clean.endsWith('@my.richfield.ac.za') ||
      clean.endsWith('@richfield.ac.za');
  if (!onDomain) return false;
  final prefix = clean.split('@').first;
  return RegExp(r'^\d{9}$').hasMatch(prefix);
}
