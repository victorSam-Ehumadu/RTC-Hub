import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Opens the change-password dialog and shows a confirmation message
/// afterward, using the caller's own (stable) context rather than the
/// dialog's own — the dialog pops itself before anything else happens, so
/// nothing here reuses a context mid-teardown.
Future<void> showChangePasswordDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ChangePasswordDialog(),
  );
  if ((changed ?? false) && context.mounted) {
    showMessage(context, 'Password changed.');
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final me = ref.read(meProvider);
    if (me == null) return;

    setState(() => _busy = true);
    try {
      // Supabase has no standalone "verify this password" call — signing in
      // again both re-authenticates and confirms the current password is
      // actually correct in one round trip.
      final auth = ref.read(authRepoProvider);
      await auth.signIn(email: me.email, password: _current.text);
      await auth.updateOwnPassword(_next.text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Current password'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (v) => passwordPolicyError(v ?? ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
              validator: (v) =>
                  v != _next.text ? "Passwords don't match" : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const DottedProgressIndicator(size: 16, color: Colors.white)
              : const Text('Change'),
        ),
      ],
    );
  }
}
