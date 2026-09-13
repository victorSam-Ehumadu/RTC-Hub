import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Moderation console.
///
/// Nothing here uses a privileged key — every action relies on `is_admin()`
/// being true inside an RLS policy or a SECURITY DEFINER function, so a
/// non-admin who reached this screen would simply get empty lists and
/// permission errors.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);

    if (me != null && !me.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Administrators only',
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Accounts'),
              Tab(text: 'Listings'),
              Tab(text: 'Flags'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OverviewTab(),
            _AccountsTab(),
            _ListingsTab(),
            _FlagsTab(),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminStatsProvider),
      child: stats.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(
          error: err,
          onRetry: () => ref.invalidate(adminStatsProvider),
        ),
        data: (s) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _StatTile(
                  label: 'Users',
                  value: s.totalUsers,
                  icon: Icons.people_outline,
                  color: roleColor('STUDENT'),
                ),
                _StatTile(
                  label: 'Awaiting approval',
                  value: s.pendingUsers,
                  icon: Icons.hourglass_top,
                  color: AppColors.points,
                ),
                _StatTile(
                  label: 'Posts',
                  value: s.totalPosts,
                  icon: Icons.article_outlined,
                  color: roleColor('ALUMNI'),
                ),
                _StatTile(
                  label: 'Bounties',
                  value: s.bounties,
                  icon: Icons.bolt,
                  color: AppColors.points,
                ),
                _StatTile(
                  label: 'Listings to review',
                  value: s.pendingOpportunities,
                  icon: Icons.work_outline,
                  color: AppColors.accent,
                ),
                _StatTile(
                  label: 'Open flags',
                  value: s.openFlags,
                  icon: Icons.flag_outlined,
                  color: AppColors.danger,
                ),
              ],
            ),
            const SectionHeader(title: 'Analytics'),
            OutlinedButton.icon(
              onPressed: () => context.push('/admin-dashboard'),
              icon: const Icon(Icons.query_stats, size: 18),
              label: const Text('Open the platform dashboard'),
            ),

            const SectionHeader(title: 'Alumni verification'),
            OutlinedButton.icon(
              onPressed: () => context.push('/admin/alumni'),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Review graduation claims'),
            ),

            const SectionHeader(title: 'Broadcast'),
            FilledButton.icon(
              onPressed: () => _announce(context, ref),
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Send an announcement'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _announce(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final body = TextEditingController();

    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: body,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send to everyone'),
          ),
        ],
      ),
    );

    final titleText = title.text;
    final bodyText = body.text;
    title.dispose();
    body.dispose();

    if (send != true || titleText.trim().isEmpty) return;

    try {
      await ref
          .read(adminRepoProvider)
          .announce(title: titleText, body: bodyText);
      if (context.mounted) showMessage(context, 'Announcement sent.');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 19, color: color),
          Text('$value', style: monoStyle(size: 24, weight: FontWeight.w800)),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsTab extends ConsumerWidget {
  const _AccountsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingUsersProvider);

    Future<void> decide(String userId, String status) async {
      try {
        await ref.read(adminRepoProvider).setUserStatus(userId, status);
        ref
          ..invalidate(pendingUsersProvider)
          ..invalidate(adminStatsProvider);
        if (context.mounted) {
          showMessage(context, 'Account ${status.toLowerCase()}.');
        }
      } catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pendingUsersProvider),
      child: pending.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(error: err),
        data: (users) {
          if (users.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  child: const EmptyState(
                    icon: Icons.verified_user_outlined,
                    title: 'Nothing to approve',
                    message: 'Business and alumni registrations appear here.',
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final user = users[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Avatar(profile: user, radius: 20),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  user.email,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          RoleBadge(role: user.role),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(38),
                                foregroundColor: AppColors.danger,
                              ),
                              onPressed: () => decide(user.id, 'REJECTED'),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(38),
                              ),
                              onPressed: () => decide(user.id, 'ACTIVE'),
                              child: const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ListingsTab extends ConsumerWidget {
  const _ListingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingOpportunitiesProvider);

    Future<void> decide(String id, String status) async {
      try {
        await ref.read(adminRepoProvider).setOpportunityStatus(id, status);
        ref
          ..invalidate(pendingOpportunitiesProvider)
          ..invalidate(adminStatsProvider);
        if (context.mounted) {
          showMessage(
            context,
            status == 'ACTIVE'
                ? 'Published — matching students were notified.'
                : 'Listing rejected.',
          );
        }
      } catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pendingOpportunitiesProvider),
      child: pending.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(error: err),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  child: const EmptyState(
                    icon: Icons.work_outline,
                    title: 'No listings waiting',
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final o = list[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${o.business?.displayName ?? 'Business'} · ${o.typeLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        o.description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(38),
                                foregroundColor: AppColors.danger,
                              ),
                              onPressed: () => decide(o.id, 'REJECTED'),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(38),
                              ),
                              onPressed: () => decide(o.id, 'ACTIVE'),
                              child: const Text('Publish'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FlagsTab extends ConsumerWidget {
  const _FlagsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(openFlagsProvider);

    Future<void> resolve(
      String flagId,
      String? postId, {
      required bool hide,
    }) async {
      try {
        await ref
            .read(adminRepoProvider)
            .resolveFlag(flagId, postId: postId, hidePost: hide);
        ref
          ..invalidate(openFlagsProvider)
          ..invalidate(adminStatsProvider);
        if (context.mounted) showMessage(context, 'Flag resolved.');
      } catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(openFlagsProvider),
      child: flags.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(error: err),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  child: const EmptyState(
                    icon: Icons.flag_outlined,
                    title: 'No open flags',
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final flag = list[i];
              final post = flag['post'] as Map<String, dynamic>?;
              final postId = post?['id'] as String?;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flag,
                              size: 16, color: AppColors.danger),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              (flag['reason'] ?? 'Reported') as String,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                      if (post != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            (post['content'] ?? '') as String,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (postId != null)
                            TextButton(
                              onPressed: () => context.push('/post/$postId'),
                              child: const Text('View'),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () =>
                                resolve(flag['id'] as String, postId, hide: false),
                            child: const Text('Dismiss'),
                          ),
                          const SizedBox(width: 6),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              backgroundColor: AppColors.danger,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                resolve(flag['id'] as String, postId, hide: true),
                            child: const Text('Hide post'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
