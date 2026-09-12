import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/post.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Edits a post you wrote.
///
/// Content and code only. Whether something is a bounty, what it is worth,
/// and which faculty it reaches are all absent by design — `trg_posts_guard`
/// reverts them anyway, but offering them would imply they are editable.
/// Turning a solved bounty back into an ordinary post, or moving a post
/// between faculties after people have read it, are not edits; they are
/// rewrites of something others already acted on.
Future<Post?> showEditPostSheet(BuildContext context, Post post) {
  return showModalBottomSheet<Post>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditPostSheet(post: post),
  );
}

class _EditPostSheet extends ConsumerStatefulWidget {
  const _EditPostSheet({required this.post});

  final Post post;

  @override
  ConsumerState<_EditPostSheet> createState() => _EditPostSheetState();
}

class _EditPostSheetState extends ConsumerState<_EditPostSheet> {
  late final _content = TextEditingController(text: widget.post.content);
  late final _code = TextEditingController(text: widget.post.codeSnippet ?? '');
  late String _language = widget.post.codeLanguage ?? kCodeLanguages.first;
  late bool _hasCode = widget.post.hasCode;
  bool _busy = false;

  @override
  void dispose() {
    _content.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_content.text.trim().isEmpty) {
      showMessage(context, 'A post needs something in it.');
      return;
    }

    setState(() => _busy = true);
    try {
      final updated = await ref.read(postRepoProvider).edit(
            widget.post.id,
            content: _content.text,
            codeLanguage: _hasCode ? _language : null,
            codeSnippet:
                _hasCode && _code.text.trim().isNotEmpty ? _code.text : null,
            // Preserved rather than dropped: the edit sheet does not offer
            // spreadsheet editing, and sending null would silently delete
            // one that is already attached.
            sheetData: widget.post.sheet?.toMap(),
          );
      if (mounted) Navigator.pop(context, updated);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.post.isBounty ? 'Edit bounty' : 'Edit post',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.post.isBounty)
                  PointsChip(points: widget.post.bountyPoints),
              ],
            ),
            if (widget.post.isBounty) ...[
              const SizedBox(height: 6),
              Text(
                'The reward and whether this is a bounty cannot be changed — '
                'people have already answered on those terms.',
                style: TextStyle(fontSize: 12, height: 1.45, color: muted),
              ),
            ],

            const SizedBox(height: 16),
            TextField(
              controller: _content,
              minLines: 3,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(alignLabelWithHint: true),
            ),

            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hasCode,
              onChanged: (v) => setState(() => _hasCode = v),
              title: const Text('Attach a snippet'),
              secondary: const Icon(Icons.code),
            ),

            if (_hasCode) ...[
              DropdownButtonFormField<String>(
                initialValue: kCodeLanguages.contains(_language)
                    ? _language
                    : kCodeLanguages.first,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  for (final l in kCodeLanguages)
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (v) => setState(() => _language = v ?? _language),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                minLines: 5,
                maxLines: 14,
                style: monoStyle(size: 12.5, weight: FontWeight.w400),
                decoration: const InputDecoration(
                  hintText: 'Your code',
                  alignLabelWithHint: true,
                ),
              ),
            ],

            if (widget.post.hasSheet) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.grid_on, size: 15, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The attached spreadsheet is kept as it is. Post a new '
                      'one to replace it.',
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 17),
              label: Text(_busy ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
