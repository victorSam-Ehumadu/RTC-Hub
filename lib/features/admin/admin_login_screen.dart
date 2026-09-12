import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Sign-in for the standalone administrator portal (`main_admin.dart`).
///
/// This is deliberately not [LoginScreen] with a role check bolted on: per
/// the hackathon brief, "administrators do not use the same registration
/// flow as other user types" and "administrator accounts must never be
/// self-registerable". There is no `Create an account` link here, and there
/// never will be — this screen only ever signs in.
///
/// Authentication still runs against the same Supabase Auth users as
/// everyone else (there is one backend, per CLAUDE.md), so a correct
/// email/password for a STUDENT, ALUMNI or BUSINESS account is a valid
/// sign-in as far as Supabase is concerned. What makes this portal separate
/// is what happens next: [_submit] re-reads the caller's own `profiles` row
/// and immediately signs back out anyone who isn't an ACTIVE admin, before
/// the router ever has a session to act on. RLS backs this up regardless —
/// `AdminScreen` re-checks `isAdmin` itself and every query it makes is
/// filtered by `is_admin()` — but bouncing the wrong role right here, with a
/// clear message, is the "protection of admin credentials" the brief asks
/// to see demonstrated.
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    final auth = ref.read(authRepoProvider);
    try {
      await auth.signIn(email: _email.text, password: _password.text);

      final profile = await auth.currentProfile();
      if (profile == null || !profile.isAdmin) {
        await auth.signOut();
        if (mounted) {
          showError(
            context,
            StateError('This portal is for Richfield administrators only.'),
          );
        }
        return;
      }
      if (!profile.isActive) {
        await auth.signOut();
        if (mounted) {
          showError(
            context,
            StateError('This admin account is ${profile.status.toLowerCase()}.'),
          );
        }
        return;
      }
      // Valid admin, active account — the router's refreshListenable picks
      // up the session and moves off /login, so there is no navigation to
      // do here.
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_email.text.contains('@')) {
      showMessage(context, 'Enter your admin email address first.');
      return;
    }
    try {
      await ref.read(authRepoProvider).sendPasswordReset(_email.text);
      if (mounted) showMessage(context, 'Password reset link sent.');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AdminWordmark(),
                    const SizedBox(height: 36),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Admin email',
                        prefixIcon: Icon(Icons.alternate_email, size: 20),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter your email address'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const DottedProgressIndicator(
                              size: 20,
                              color: Colors.white,
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'There is no self-registration here. Admin accounts are '
                      'provisioned directly by an existing administrator.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminWordmark extends StatelessWidget {
  const _AdminWordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.admin_panel_settings_outlined,
            size: 36,
            color: AppColors.danger,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'RTC Hub Admin',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Richfield staff access only.',
          textAlign: TextAlign.center,
          style: monoStyle(
            size: 12,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
