import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/opportunity.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../shell/app_shell.dart';

/// Two different screens behind one tab: businesses manage their listings,
/// everyone else browses and applies.
class OpportunitiesScreen extends ConsumerWidget {
  const OpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) return const Scaffold(body: Loading());

    return me.isBusiness ? const _BusinessView() : const _SeekerView();
  }
}

class _SeekerView extends ConsumerStatefulWidget {
  const _SeekerView();

  @override
  ConsumerState<_SeekerView> createState() => _SeekerViewState();
}

class _SeekerViewState extends ConsumerState<_SeekerView> {
  bool _matchedOnly = true;

  @override
  Widget build(BuildContext context) {
    final listings = _matchedOnly
        ? ref.watch(matchedOpportunitiesProvider)
        : ref.watch(opportunitiesProvider);

    return Scaffold(
      appBar: const HubAppBar(title: 'Opportunities'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('For you'),
                  icon: Icon(Icons.auto_awesome, size: 15),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('All'),
                  icon: Icon(Icons.list, size: 15),
                ),
              ],
              selected: {_matchedOnly},
              onSelectionChanged: (s) =>
                  setState(() => _matchedOnly = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref
                  ..invalidate(matchedOpportunitiesProvider)
                  ..invalidate(opportunitiesProvider);
              },
              child: listings.when(
                loading: () => const OpportunityListSkeleton(),
                error: (err, _) => ErrorView(error: err),
                data: (list) {
                  if (list.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.55,
                          child: EmptyState(
                            icon: Icons.work_outline,
                            title: _matchedOnly
                                ? 'No matches yet'
                                : 'No open opportunities',
                            message: _matchedOnly
                                ? 'Matching uses your skills, faculty and year. '
                                    'Add a few skills to your profile.'
                                : 'Check back once businesses start posting.',
                            action: _matchedOnly
                                ? OutlinedButton(
                                    onPressed: () =>
                                        setState(() => _matchedOnly = false),
                                    child: const Text('Browse all'),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _OpportunityCard(
                      opportunity: list[i],
                      onApply: () => _apply(list[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(Opportunity opportunity) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Apply: ${opportunity.title}'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'Why you? Keep it short.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;

    try {
      await ref
          .read(opportunityRepoProvider)
          .apply(opportunity.id, coverNote: note.trim());
      ref
        ..invalidate(matchedOpportunitiesProvider)
        ..invalidate(opportunitiesProvider);
      if (mounted) showMessage(context, 'Application sent.');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity, this.onApply});

  final Opportunity opportunity;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(profile: opportunity.business, radius: 19),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opportunity.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      Text(
                        opportunity.business?.displayName ?? 'A business',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                if ((opportunity.matchScore ?? 0) > 0)
                  TagChip(
                    label: '${opportunity.matchScore} match',
                    color: AppColors.accent,
                    icon: Icons.auto_awesome,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              opportunity.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.45, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                TagChip(
                  label: opportunity.typeLabel,
                  color: roleColor('ALUMNI'),
                  icon: Icons.badge_outlined,
                ),
                TagChip(
                  label: opportunity.whereLabel,
                  color: AppColors.darkMuted,
                  icon: Icons.place_outlined,
                ),
                for (final skill in opportunity.requiredSkills.take(3))
                  TagChip(label: skill, color: roleColor('STUDENT')),
              ],
            ),
            if (onApply != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: opportunity.hasApplied
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check, size: 17),
                        label: const Text('Applied'),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: onApply,
                        child: const Text('Apply'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What a BUSINESS account sees: their own listings and who applied.
class _BusinessView extends ConsumerWidget {
  const _BusinessView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(myOpportunitiesProvider);

    return Scaffold(
      appBar: const HubAppBar(title: 'Your listings'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/post-opportunity'),
        icon: const Icon(Icons.add),
        label: const Text('Post'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myOpportunitiesProvider),
        child: listings.when(
          loading: () => const Loading(),
          error: (err, _) => ErrorView(error: err),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: EmptyState(
                      icon: Icons.post_add,
                      title: 'No listings yet',
                      message: 'Posted roles are reviewed by an administrator '
                          'before students see them.',
                      action: FilledButton(
                        onPressed: () => context.push('/post-opportunity'),
                        child: const Text('Post an opportunity'),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _MyListingCard(opportunity: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _MyListingCard extends ConsumerWidget {
  const _MyListingCard({required this.opportunity});

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = switch (opportunity.status) {
      'ACTIVE' => AppColors.accent,
      'PENDING' => AppColors.points,
      _ => AppColors.danger,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    opportunity.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                TagChip(label: opportunity.status, color: statusColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${opportunity.typeLabel} · ${opportunity.whereLabel}',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
            if (opportunity.status == 'PENDING')
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Waiting for administrator approval.',
                  style: TextStyle(fontSize: 12, color: AppColors.points),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
              onPressed: () => _showApplicants(context, ref),
              icon: const Icon(Icons.people_outline, size: 17),
              label: Text('Applicants (${opportunity.applicationCount})'),
            ),
          ],
        ),
      ),
    );
  }

  void _showApplicants(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (dialogContext) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Consumer(
          builder: (context, ref, _) {
            final applications =
                ref.watch(applicationsForProvider(opportunity.id));
            return applications.when(
              loading: () => const Loading(),
              error: (err, _) => ErrorView(error: err),
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'No applicants yet',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final app = list[i];
                        return ListTile(
                          onTap: () {
                            Navigator.pop(dialogContext);
                            context.push('/user/${app.applicantId}');
                          },
                          leading: Avatar(profile: app.applicant, radius: 20),
                          title: Text(
                            app.applicant?.displayName ?? 'Applicant',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            app.coverNote?.isNotEmpty == true
                                ? app.coverNote!
                                : (app.applicant?.subtitle ?? ''),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TagChip(
                            label: app.status,
                            color: app.status == 'SHORTLISTED'
                                ? AppColors.accent
                                : AppColors.darkMuted,
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }
}
