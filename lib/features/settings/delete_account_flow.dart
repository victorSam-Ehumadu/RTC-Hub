import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Password, then a Yes/No confirmation, then the actual delete — in that
/// order, so a wrong password never even reaches the "are you sure" step.
/// See migration 0019's delete_own_account() for the backend half.
Future<void> showDeleteAccountFlow(BuildContext context, WidgetRef ref) async {
  final me = ref.read(meProvider);
  if (me == null) return;

  final password = await showDialog<String>(
    context: context,
    builder: (_) => const _PasswordDialog(),
  );
  if (password == null || password.isEmpty || !context.mounted) return;

  try {
    await ref.read(authRepoProvider).signIn(email: me.email, password: password);
  } catch (error) {
    if (context.mounted) showError(context, error);
    return;
  }
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text(
        'This permanently deletes your account and everything in it — '
        'posts, messages, connections, Logic Points. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete my account'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final auth = ref.read(authRepoProvider);
    await auth.deleteOwnAccount();
    await auth.signOut();
    if (context.mounted) context.go('/login');
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your password'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
          validator: (v) =>
              (v == null || v.isEmpty) ? 'Enter your password' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _password.text);
            }
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
