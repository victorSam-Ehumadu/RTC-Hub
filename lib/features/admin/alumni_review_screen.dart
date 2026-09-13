import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../core/theme.dart';
import '../../models/verification.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// Where an administrator decides an alumni claim (§2.1).
///
/// The point of this screen is that the claim and the evidence appear
/// together. The old flow put alumni in the same PENDING list as businesses,
/// where an administrator saw a name and a role and nothing to check against
/// — which is approval by vibe, and is what §2.1 means by leaving the
/// challenge as a gap.
class AlumniReviewScreen extends ConsumerWidget {
  const AlumniReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me != null && !me.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alumni verification')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Administrators only',
        ),
      );
    }

    final status = ref.watch(alumniQueueStatusProvider);
    final queue = ref.watch(alumniQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alumni verification'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PENDING', label: Text('To review')),
                ButtonSegment(value: 'APPROVED', label: Text('Approved')),
                ButtonSegment(value: 'REJECTED', label: Text('Rejected')),
              ],
              selected: {status},
              onSelectionChanged: (s) =>
                  ref.read(alumniQueueStatusProvider.notifier).state = s.first,
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(alumniQueueProvider),
        child: queue.when(
          loading: () => const TileListSkeleton(count: 3),
          error: (err, _) => ErrorView(
            error: err,
            onRetry: () => ref.invalidate(alumniQueueProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: EmptyState(
                      icon: status == 'PENDING'
                          ? Icons.inbox_outlined
                          : Icons.history,
                      title: switch (status) {
                        'PENDING' => 'Nothing waiting',
                        'APPROVED' => 'Nobody approved yet',
                        _ => 'Nothing rejected',
                      },
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
              itemCount: list.length,
              itemBuilder: (_, i) => _ClaimCard(claim: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ClaimCard extends ConsumerStatefulWidget {
  const _ClaimCard({required this.claim});

  final AlumniVerification claim;

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  bool _busy = false;

  Future<void> _openEvidence() async {
    setState(() => _busy = true);
    try {
      final url =
          await ref.read(verificationRepoProvider).evidenceUrl(widget.claim.id);
      final ok = await launchUrlString(url, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showMessage(context, 'Could not open the document.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide({required bool approve}) async {
    String? note;

    // A rejection the applicant cannot act on wastes everyone's time, so
    // ask for a reason before recording one.
    if (!approve) {
      final controller = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Why can this not be confirmed?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'The photo is too blurry to read the name.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (note == null) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(verificationRepoProvider).decide(
            widget.claim.id,
            approve: approve,
            reviewerNote: note,
          );
      ref
        ..invalidate(alumniQueueProvider)
        ..invalidate(pendingUsersProvider)
        ..invalidate(adminStatsProvider);
      if (mounted) {
        showMessage(
          context,
          approve ? 'Verified. Their account is now active.' : 'Rejected.',
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
    final c = widget.claim;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      roleColor('ALUMNI').withValues(alpha: 0.15),
                  backgroundImage: c.avatarUrl == null
                      ? null
                      : NetworkImage(c.avatarUrl!),
                  child: c.avatarUrl != null
                      ? null
                      : Text(
                          (c.fullName ?? '?').isEmpty
                              ? '?'
                              : c.fullName![0].toUpperCase(),
                          style: TextStyle(
                            color: roleColor('ALUMNI'),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.fullName ?? 'Unknown',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                      if (c.email != null)
                        Text(
                          c.email!,
                          style: TextStyle(fontSize: 11.5, color: muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (!c.isPending)
                  TagChip(
                    label: c.status,
                    color: c.isApproved ? AppColors.success : AppColors.danger,
                    icon: c.isApproved ? Icons.check_circle : Icons.cancel,
                  ),
              ],
            ),

            const SizedBox(height: 14),
            // The claim, spelled out, so a reviewer is checking the document
            // against something specific rather than forming an impression.
            _Claim(label: 'Student number', value: c.studentNumber, mono: true),
            _Claim(label: 'Graduated', value: '${c.graduationYear}'),
            if (c.course != null) _Claim(label: 'Qualification', value: c.course!),
            if (c.campus != null) _Claim(label: 'Campus', value: c.campus!),
            _Claim(label: 'Document', value: c.evidenceLabel),

            if (c.note != null && c.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(9),
                  border:
                      Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Text(
                  c.note!,
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],

            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openEvidence,
              icon: const Icon(Icons.description_outlined, size: 17),
              label: const Text('Open the document'),
            ),

            if (c.isPending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _decide(approve: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _decide(approve: true),
                      child: const Text('Verify'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Reject if you cannot tell. A resubmission costs them a '
                'minute; a wrong approval puts an unverified stranger in the '
                'alumni network.',
                style: TextStyle(fontSize: 11, height: 1.4, color: muted),
              ),
            ] else if (c.reviewerNote != null) ...[
              const SizedBox(height: 10),
              Text(
                'Reason given: ${c.reviewerNote}',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Claim extends StatelessWidget {
  const _Claim({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label, style: TextStyle(fontSize: 11.5, color: muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? monoStyle(size: 12.5, weight: FontWeight.w700)
                  : const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
