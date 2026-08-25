import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Top contributors, straight from the `leaderboard` view.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider);
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: board.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(
          error: err,
          onRetry: () => ref.invalidate(leaderboardProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.leaderboard_outlined,
              title: 'Nobody on the board yet',
              message: 'Logic Points are earned by solving bounties.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final entry = entries[i];
              final isMe = entry.id == me?.id;
              final rank = i + 1;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isMe
                      ? AppColors.accent.withValues(alpha: 0.08)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMe
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: ListTile(
                  onTap: () => context.push('/user/${entry.id}'),
                  leading: SizedBox(
                    width: 62,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '$rank',
                            style: monoStyle(
                              size: 14,
                              weight: FontWeight.w800,
                              color: switch (rank) {
                                1 => AppColors.points,
                                2 => AppColors.darkMuted,
                                3 => const Color(0xFFB45309),
                                _ => Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              },
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 17,
                          backgroundColor:
                              AppColors.accent.withValues(alpha: 0.18),
                          child: Text(
                            entry.fullName.isEmpty
                                ? '?'
                                : entry.fullName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    entry.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    entry.course ?? '${entry.skillCount} skills',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PointsChip(points: entry.totalPoints),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
