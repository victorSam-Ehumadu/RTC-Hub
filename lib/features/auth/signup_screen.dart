import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Registration. Which fields appear depends on the role, and the student
/// email rule is checked here as well as in `handle_new_user()`.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  // Free-text email, used for ALUMNI/BUSINESS. STUDENT instead uses
  // _emailLocal + _emailDomain below — registration is domain-restricted
  // per the hackathon guidelines, so a dropdown of the allowed domains
  // replaces free entry rather than just validating it after the fact.
  final _email = TextEditingController();
  final _emailLocal = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _fullName = TextEditingController();
  final _company = TextEditingController();
  final _industry = TextEditingController();
  final _studentNumber = TextEditingController();
  final _graduationYear = TextEditingController();

  String _role = 'STUDENT';
  String _emailDomain = kStudentEmailDomains.first;
  String? _faculty;
  String? _course;
  String? _year;
  String? _campus;
  int? _enrollmentYear;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _emailLocal.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _fullName.dispose();
    _company.dispose();
    _industry.dispose();
    _studentNumber.dispose();
    _graduationYear.dispose();
    super.dispose();
  }

  bool get _isStudentish => _role == 'STUDENT' || _role == 'ALUMNI';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final email = _role == 'STUDENT'
        ? '${_emailLocal.text.trim()}@$_emailDomain'
        : _email.text;
    try {
      await ref.read(authRepoProvider).signUp(
            email: email,
            password: _password.text,
            fullName: _fullName.text,
            role: _role,
            faculty: _isStudentish ? _faculty : null,
            course: _isStudentish ? _course : null,
            academicYear: _isStudentish ? _year : null,
            campus: _isStudentish ? _campus : null,
            enrollmentYear: _isStudentish ? _enrollmentYear : null,
            graduationYear:
                _role == 'ALUMNI' ? int.tryParse(_graduationYear.text.trim()) : null,
            studentNumber:
                _role == 'ALUMNI' ? _studentNumber.text.trim() : null,
            companyName: _role == 'BUSINESS' ? _company.text : null,
            industry: _role == 'BUSINESS' ? _industry.text : null,
          );
      if (!mounted) return;

      // Show post-signup loading screen for all roles before routing to feed/profile
      context.go('/post-signup-loading');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'I am a'),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'STUDENT', label: Text('Student')),
                      ButtonSegment(value: 'ALUMNI', label: Text('Alumni')),
                      ButtonSegment(value: 'BUSINESS', label: Text('Business')),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() {
                      _role = s.first;
                      _faculty = null;
                      _course = null;
                      _year = _role == 'ALUMNI' ? 'Alumni' : null;
                      _campus = null;
                      _enrollmentYear = null;
                    }),
                  ),
                  if (_role != 'STUDENT')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _Notice(
                        icon: Icons.info_outline,
                        text: '$_role accounts are reviewed by an administrator '
                            'before they can sign in.',
                      ),
                    ),

                  const SectionHeader(title: 'Details'),
                  TextFormField(
                    controller: _fullName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Enter your full name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  if (_role == 'STUDENT')
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: _emailLocal,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Student number',
                              hintText: '202512345',
                            ),
                            validator: (v) =>
                                RegExp(r'^\d{9}$').hasMatch(v?.trim() ?? '')
                                    ? null
                                    : '9 digits',
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 16, left: 4, right: 4),
                          child: Text('@', style: TextStyle(fontSize: 16)),
                        ),
                        Expanded(
                          flex: 6,
                          child: DropdownButtonFormField<String>(
                            initialValue: _emailDomain,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Domain'),
                            items: [
                              for (final d in kStudentEmailDomains)
                                DropdownMenuItem(
                                  value: d,
                                  child:
                                      Text(d, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _emailDomain = v!),
                          ),
                        ),
                      ],
                    )
                  else
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration:
                          const InputDecoration(labelText: 'Email', hintText: 'you@company.co.za'),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        return value.contains('@')
                            ? null
                            : 'Enter your email address';
                      },
                    ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      helperText: '8+ characters, upper and lower case, a '
                          'number and a special character',
                      helperMaxLines: 2,
                    ),
                    validator: (v) => passwordPolicyError(v ?? ''),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm password'),
                    validator: (v) => v != _password.text
                        ? 'Passwords don\'t match'
                        : null,
                  ),

                  if (_isStudentish) ...[
                    const SectionHeader(title: 'Studies'),
                    DropdownButtonFormField<String>(
                      initialValue: _faculty,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Faculty'),
                      items: [
                        for (final f in kFaculties)
                          DropdownMenuItem(value: f.code, child: Text(f.name)),
                      ],
                      onChanged: (v) => setState(() {
                        _faculty = v;
                        _course = null;
                      }),
                      validator: (v) => v == null ? 'Pick your faculty' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _course,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Course'),
                      items: [
                        for (final c in coursesForFaculty(_faculty))
                          DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _course = v),
                      validator: (v) => v == null ? 'Pick your course' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _year,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Year'),
                      items: [
                        for (final y in kAcademicYears)
                          DropdownMenuItem(value: y, child: Text(y)),
                      ],
                      onChanged: (v) => setState(() => _year = v),
                      validator: (v) => v == null ? 'Pick your year' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _campus,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Campus'),
                      items: [
                        for (final c in kCampuses)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _campus = v),
                      validator: (v) => v == null ? 'Pick your campus' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: _enrollmentYear,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Year of enrollment'),
                      items: [
                        for (final y in kYearOptions(after: 0))
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (v) => setState(() => _enrollmentYear = v),
                      validator: (v) =>
                          v == null ? 'Pick your enrollment year' : null,
                    ),
                  ],

                  if (_role == 'ALUMNI') ...[
                    const SectionHeader(title: 'Verify your studies'),
                    _Notice(
                      icon: Icons.info_outline,
                      text: "If these match an account you held as a "
                          "student here, an admin reviewing your signup will "
                          "see that and can approve you faster. You can also "
                          "optionally upload a document afterwards — a "
                          "degree certificate, graduation letter, or old "
                          "student card — either way, either helps.",
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _studentNumber,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Student number',
                        hintText: 'The number you studied under',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your student number'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _graduationYear,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Graduation year',
                        hintText: 'e.g. 2023',
                      ),
                      validator: (v) {
                        final year = int.tryParse(v?.trim() ?? '');
                        final thisYear = DateTime.now().year;
                        if (year == null || year < 1950 || year > thisYear) {
                          return 'Enter a valid graduation year';
                        }
                        return null;
                      },
                    ),
                  ],

                  if (_role == 'BUSINESS') ...[
                    const SectionHeader(title: 'Company'),
                    TextFormField(
                      controller: _company,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Company name'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your company name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _industry,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Industry'),
                    ),
                  ],

                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const DottedProgressIndicator(
                            size: 20,
                            color: Colors.white,
                          )
                        : const Text('Create account'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('I already have an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.points.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.points.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.points),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
