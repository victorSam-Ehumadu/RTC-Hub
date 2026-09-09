import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Composer for a normal post or a bounty.
///
/// The bounty value is not settable here on purpose: `trg_posts_guard` sets every
/// new bounty to 10 points, and `escalate_bounties()` raises unsolved ones
/// over time, so there is nothing for the client to decide.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.asBounty = false});

  final bool asBounty;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _content = TextEditingController();
  final _code = TextEditingController();
  final _module = TextEditingController();

  late bool _isBounty = widget.asBounty;
  bool _attachCode = false;
  String _language = 'dart';
  bool _busy = false;

  @override
  void dispose() {
    _content.dispose();
    _code.dispose();
    _module.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_content.text.trim().isEmpty) {
      showMessage(context, 'Write something first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(postRepoProvider).create(
            content: _content.text,
            type: _isBounty
                ? 'BOUNTY'
                : (_attachCode ? 'CODE' : 'TEXT'),
            codeLanguage: _attachCode ? _language : null,
            codeSnippet: _attachCode && _code.text.trim().isNotEmpty
                ? _code.text
                : null,
            isBounty: _isBounty,
            bountyModule: _isBounty && _module.text.trim().isNotEmpty
                ? _module.text.trim()
                : null,
          );

      ref.invalidate(feedProvider);
      ref.invalidate(bountiesProvider);

      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        _isBounty ? 'Bounty posted — 10 LP on offer.' : 'Posted.',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isBounty ? 'Post a bounty' : 'New post'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const DottedProgressIndicator(size: 16)
                : const Text('Post'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isBounty,
              onChanged: (v) => setState(() {
                _isBounty = v;
                if (v) _attachCode = true;
              }),
              title: const Text('Ask as a bounty'),
              subtitle: Text(
                'Offers 10 Logic Points to whoever solves it. You pick the '
                'accepted answer.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
              secondary: const Icon(Icons.bolt, color: AppColors.points),
            ),
            const Divider(height: 24),

            TextField(
              controller: _content,
              maxLines: 6,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isBounty
                    ? 'What are you stuck on? Describe what you expected and '
                        'what actually happened.'
                    : 'Share what you are building…',
              ),
            ),

            if (_isBounty) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _module,
                decoration: const InputDecoration(
                  labelText: 'Module (optional)',
                  hintText: 'e.g. Advanced Java',
                  prefixIcon: Icon(Icons.school_outlined, size: 20),
                ),
              ),
            ],

            const SectionHeader(title: 'Code'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _attachCode,
              onChanged: (v) => setState(() => _attachCode = v),
              title: const Text('Attach a snippet'),
              secondary: const Icon(Icons.code),
            ),

            if (_attachCode) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  for (final lang in kCodeLanguages)
                    DropdownMenuItem(value: lang, child: Text(lang)),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'dart'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                maxLines: 14,
                minLines: 6,
                style: monoStyle(size: 13),
                decoration: const InputDecoration(
                  hintText: 'Paste your code here',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
