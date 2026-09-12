import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/recommendation.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Written recommendations on a profile — §2.3.
///
/// On your own profile this also surfaces the approval queue, because a
/// recommendation nobody knows about is the same as no recommendation. On
/// someone else's it offers to write one.
class RecommendationsSection extends ConsumerWidget {
  const RecommendationsSection({
    super.key,
    required this.userId,
    required this.isSelf,
    this.subjectName,
  });

  final String userId;
  final bool isSelf;
  final String? subjectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendations = ref.watch(recommendationsProvider(userId));

    return recommendations.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (all) {
        // The RLS policy returns pending rows only to the two people
        // involved, so this split needs no extra query.
        final approved = all.where((r) => r.approved).toList();
        final pending = all.where((r) => !r.approved).toList();

        if (approved.isEmpty && pending.isEmpty && !isSelf) {
          return _WriteOne(userId: userId, subjectName: subjectName);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Recommendations (${approved.length})',
              action: isSelf
                  ? null
                  : TextButton(
                      onPressed: () =>
                          _write(context, ref, userId, subjectName),
                      child: const Text('Write one'),
                    ),
            ),

            if (isSelf && pending.isNotEmpty) ...[
              _PendingBanner(count: pending.length),
              const SizedBox(height: 10),
              for (final r in pending)
                _RecommendationCard(
                  recommendation: r,
                  showApproval: true,
                  onChanged: () => _refresh(ref, userId),
                ),
              const SizedBox(height: 6),
            ],

            if (approved.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isSelf
                      ? 'None yet. Recommendations from lecturers, teammates '
                          'and colleagues appear here once you approve them.'
                      : 'No recommendations yet.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              )
            else
              for (final r in approved)
                _RecommendationCard(
                  recommendation: r,
                  showApproval: isSelf,
                  onChanged: () => _refresh(ref, userId),
                ),
          ],
        );
      },
    );
  }

  void _refresh(WidgetRef ref, String userId) {
    ref
      ..invalidate(recommendationsProvider(userId))
      ..invalidate(pendingRecommendationsProvider);
  }

  static Future<void> _write(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String? name,
  ) async {
    final written = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WriteSheet(subjectId: userId, subjectName: name),
    );
    if (written != true) return;
    ref.invalidate(recommendationsProvider(userId));
    if (context.mounted) {
      showMessage(context, 'Sent. It appears once they approve it.');
    }
  }
}

class _WriteOne extends ConsumerWidget {
  const _WriteOne({required this.userId, this.subjectName});

  final String userId;
  final String? subjectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Recommendations'),
        OutlinedButton.icon(
          onPressed: () => RecommendationsSection._write(
              context, ref, userId, subjectName),
          icon: const Icon(Icons.rate_review_outlined, size: 17),
          label: const Text('Write a recommendation'),
        ),
      ],
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.points.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.points.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.drafts_outlined, size: 17, color: AppColors.points),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'One recommendation is waiting for your approval.'
                  : '$count recommendations are waiting for your approval.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends ConsumerWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.showApproval,
    required this.onChanged,
  });

  final Recommendation recommendation;
  final bool showApproval;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = recommendation;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: r.isPending
              ? AppColors.points.withValues(alpha: 0.45)
              : Theme.of(context).colorScheme.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/user/${r.authorId}'),
                child: Avatar(profile: r.author, radius: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.author?.displayName ?? 'Unknown',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (r.relationship != null)
                      Text(
                        r.relationship!,
                        style: TextStyle(fontSize: 11.5, color: muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (r.isPending)
                const TagChip(
                  label: 'PENDING',
                  color: AppColors.points,
                  icon: Icons.schedule,
                ),
            ],
          ),
          const SizedBox(height: 11),
          Text(r.body, style: const TextStyle(height: 1.5, fontSize: 13.5)),

          if (showApproval) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (r.isPending)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () async {
                      try {
                        await ref
                            .read(engagementRepoProvider)
                            .setApproved(r.id, true);
                        onChanged();
                      } catch (error) {
                        if (context.mounted) showError(context, error);
                      }
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve'),
                  )
                else
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await ref
                            .read(engagementRepoProvider)
                            .setApproved(r.id, false);
                        onChanged();
                      } catch (error) {
                        if (context.mounted) showError(context, error);
                      }
                    },
                    icon: const Icon(Icons.visibility_off_outlined, size: 16),
                    label: const Text('Hide'),
                  ),
                TextButton(
                  onPressed: () async {
                    final gone = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Delete this recommendation?'),
                        content: const Text('It cannot be recovered.'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (gone != true) return;
                    try {
                      await ref.read(engagementRepoProvider).remove(r.id);
                      onChanged();
                    } catch (error) {
                      if (context.mounted) showError(context, error);
                    }
                  },
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Composer. The subject approves before it appears, which the copy says
/// plainly — otherwise people write one, see nothing, and write it again.
class _WriteSheet extends ConsumerStatefulWidget {
  const _WriteSheet({required this.subjectId, this.subjectName});

  final String subjectId;
  final String? subjectName;

  @override
  ConsumerState<_WriteSheet> createState() => _WriteSheetState();
}

class _WriteSheetState extends ConsumerState<_WriteSheet> {
  final _body = TextEditingController();
  final _relationship = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    _relationship.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (text.length < 20) {
      showMessage(context, 'Write a little more — at least a sentence.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(engagementRepoProvider).write(
            subjectId: widget.subjectId,
            body: text,
            relationship: _relationship.text,
          );
      if (mounted) Navigator.pop(context, true);
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
    final name = widget.subjectName ?? 'them';

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
            Text(
              'Recommend $name',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'They approve it before it appears on their profile. Say what '
              'you worked on together and what they are good at.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _relationship,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'How do you know them?',
                hintText: 'Group project in Advanced Java',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 5,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What are they like to work with?',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 17),
              label: Text(_busy ? 'Sending…' : 'Send for approval'),
            ),
          ],
        ),
      ),
    );
  }
}
