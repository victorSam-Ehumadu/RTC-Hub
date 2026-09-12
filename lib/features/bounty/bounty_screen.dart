import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../feed/post_card.dart';
import '../shell/app_shell.dart';

/// The bounty board — open problems ranked by the points on offer.
class BountyScreen extends ConsumerWidget {
  const BountyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bounties = ref.watch(bountiesProvider);
    final faculty = ref.watch(bountyFacultyProvider);

    return Scaffold(
      appBar: HubAppBar(
        title: 'Bounties',
        actions: [
          IconButton(
            tooltip: 'Leaderboard',
            onPressed: () => context.push('/leaderboard'),
            icon: const Icon(Icons.leaderboard_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/compose?bounty=1'),
        icon: const Icon(Icons.bolt),
        label: const Text('Ask'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: faculty == null,
                  onSelected: (_) =>
                      ref.read(bountyFacultyProvider.notifier).state = null,
                ),
                const SizedBox(width: 8),
                for (final f in kFaculties) ...[
                  FilterChip(
                    label: Text(f.code == 'IT' ? 'IT' : 'Business'),
                    selected: faculty == f.code,
                    onSelected: (_) => ref
                        .read(bountyFacultyProvider.notifier)
                        .state = faculty == f.code ? null : f.code,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(bountiesProvider),
              child: bounties.when(
                loading: () => const PostListSkeleton(),
                error: (err, _) => ErrorView(
                  error: err,
                  onRetry: () => ref.invalidate(bountiesProvider),
                ),
                data: (posts) {
                  if (posts.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.55,
                          child: EmptyState(
                            icon: Icons.bolt_outlined,
                            title: 'No open bounties',
                            message:
                                'Stuck on something? Post it as a bounty and '
                                'put 10 Logic Points on the answer.',
                            action: FilledButton(
                              onPressed: () => context.push('/compose?bounty=1'),
                              child: const Text('Post a bounty'),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: posts.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      if (i == 0) return const _BoardSummary();
                      return PostCard(post: posts[i - 1]);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardSummary extends ConsumerWidget {
  const _BoardSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) return const SizedBox.shrink();

    final points = ref.watch(logicPointsProvider(me.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.points.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.bolt, color: AppColors.points),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Logic Points',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text(
                    'Earned by solving other people’s problems.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${points.valueOrNull ?? 0}',
              style: monoStyle(
                size: 24,
                weight: FontWeight.w800,
                color: AppColors.points,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
