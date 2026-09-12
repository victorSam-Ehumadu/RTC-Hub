import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/auth_repository.dart';
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _company = TextEditingController();
  final _industry = TextEditingController();

  String _role = 'STUDENT';
  String? _faculty;
  String? _course;
  String? _year;

  /// Which faculties a business wants content from. Students and alumni never
  /// answer this — `trg_profiles_interests` derives it from their faculty.
  final _interests = <String>{'IT', 'BUSINESS'};

  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _company.dispose();
    _industry.dispose();
    super.dispose();
  }

  bool get _isStudentish => _role == 'STUDENT' || _role == 'ALUMNI';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final outcome = await ref.read(authRepoProvider).signUp(
            email: _email.text,
            password: _password.text,
            fullName: _fullName.text,
            role: _role,
            faculty: _isStudentish ? _faculty : null,
            course: _isStudentish ? _course : null,
            academicYear: _isStudentish ? _year : null,
            companyName: _role == 'BUSINESS' ? _company.text : null,
            industry: _role == 'BUSINESS' ? _industry.text : null,
            contentInterests:
                _role == 'BUSINESS' ? _interests.toList() : null,
          );
      if (!mounted) return;

      switch (outcome) {
        case SignUpOutcome.alreadyRegistered:
          showMessage(
            context,
            'That address already has an account. Try signing in instead.',
          );

        case SignUpOutcome.confirmEmail:
          // No session, so the router will not move on its own. Say what has
          // to happen next rather than leaving the user on a form that looks
          // like it failed.
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => _ConfirmEmailDialog(
              email: _email.text.trim().toLowerCase(),
              onResend: () =>
                  ref.read(authRepoProvider).resendConfirmation(_email.text),
            ),
          );
          if (mounted) context.go('/login');

        case SignUpOutcome.signedIn:
          // A session exists, so the redirect takes it from here.
          showMessage(
            context,
            _role == 'STUDENT'
                ? 'Welcome to RTC Hub.'
                : 'Registration submitted. An administrator will review your '
                    'account.',
          );
      }
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
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: _role == 'STUDENT'
                          ? '202512345@my.richfield.ac.za'
                          : 'you@company.co.za',
                      helperText: _role == 'STUDENT'
                          ? 'Richfield or AAA address, 9-digit student number'
                          : null,
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (!value.contains('@')) return 'Enter your email address';
                      if (_role == 'STUDENT' && !isValidStudentEmail(value)) {
                        return 'Must be a Richfield or AAA address with a '
                            '9-digit prefix';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Use at least 8 characters'
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

                    const SectionHeader(title: 'Talent you are looking for'),
                    Text(
                      'Richfield has two faculties. Pick the ones you recruit '
                      'from — it decides whose posts you see and who sees '
                      'yours. You can change this later.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final f in kFaculties)
                      CheckboxListTile(
                        value: _interests.contains(f.code),
                        onChanged: (on) => setState(() {
                          if (on == true) {
                            _interests.add(f.code);
                          } else if (_interests.length > 1) {
                            // Never let a business end up seeing nothing.
                            _interests.remove(f.code);
                          }
                        }),
                        title: Text(f.name),
                        subtitle: Text(
                          f.code == 'IT'
                              ? 'Developers, analysts, forensics'
                              : 'Commerce, administration, management',
                          style: const TextStyle(fontSize: 12),
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
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

/// Shown when the project requires email confirmation.
///
/// The address is repeated back because the most common reason a
/// confirmation never arrives is a typo in the field the user can no longer
/// see.
class _ConfirmEmailDialog extends StatefulWidget {
  const _ConfirmEmailDialog({required this.email, required this.onResend});

  final String email;
  final Future<void> Function() onResend;

  @override
  State<_ConfirmEmailDialog> createState() => _ConfirmEmailDialogState();
}

class _ConfirmEmailDialogState extends State<_ConfirmEmailDialog> {
  bool _resent = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.mark_email_unread_outlined, size: 32),
      title: const Text('Confirm your email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your account exists, but you need to confirm it before you can '
            'sign in. We sent a link to:',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 10),
          SelectableText(
            widget.email,
            textAlign: TextAlign.center,
            style: monoStyle(size: 13, weight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _resent || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.onResend();
                    if (mounted) setState(() => _resent = true);
                  } catch (error) {
                    if (context.mounted) showError(context, error);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(_resent ? 'Sent again' : 'Resend'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}
