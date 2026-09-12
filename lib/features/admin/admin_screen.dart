import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../models/profile.dart';
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
      onRefresh: () async {
        ref
          ..invalidate(adminStatsProvider)
          ..invalidate(adminDashboardProvider);
      },
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
            // §2.7's platform-level metrics: users by type, monthly active
            // users, registrations over time, content volume, and the
            // business approval pipeline. Flagged content count is the
            // "Open flags" tile above — an icon + colour + number is
            // already a visual indicator, so it isn't repeated as a chart.
            const _PlatformAnalytics(),
            const SectionHeader(title: 'Broadcast'),
            FilledButton.icon(
              onPressed: () => _announce(context, ref),
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Send an announcement'),
            ),
            const SectionHeader(title: 'Admins'),
            OutlinedButton.icon(
              onPressed: () => _addAdmin(context, ref),
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
              label: const Text('Add an administrator'),
            ),
          ],
        ),
      ),
    );
  }

  /// Looks up an existing account by email, confirms, then grants ADMIN.
  ///
  /// Deliberately two steps rather than one dialog: promoting the wrong
  /// account by a typo'd email is the one mistake here worth an extra click
  /// to avoid.
  Future<void> _addAdmin(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();

    final found = await showDialog<Profile?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add an administrator'),
        content: TextField(
          controller: email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => Navigator.pop(dialogContext),
          decoration: const InputDecoration(
            labelText: 'Their account email',
            hintText: 'name@richfield.ac.za',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final profile =
                  await ref.read(adminRepoProvider).findByEmail(email.text);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, profile);
              }
            },
            child: const Text('Look up'),
          ),
        ],
      ),
    );
    final emailText = email.text;
    email.dispose();

    if (found == null) {
      if (context.mounted) {
        showMessage(
          context,
          'No account found for "$emailText".',
        );
      }
      return;
    }
    if (found.isAdmin) {
      if (context.mounted) {
        showMessage(context, '${found.displayName} is already an administrator.');
      }
      return;
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Grant admin access?'),
        content: Text(
          '${found.displayName} (${found.email}) is currently a '
          '${found.role} account. Making them an administrator gives them '
          'full platform access, including account and content moderation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Make administrator'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminRepoProvider).promoteToAdmin(found.id);
      ref
        ..invalidate(adminStatsProvider)
        ..invalidate(adminDashboardProvider);
      if (context.mounted) {
        showMessage(context, '${found.displayName} is now an administrator.');
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _announce(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final body = TextEditingController();

    final send = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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

/// §2.7's platform-level admin metrics, charted. Watches its own provider
/// separately from [adminStatsProvider] so a failure here (a new RPC that
/// hasn't run yet, say) doesn't take down the action-grid tiles above it.
class _PlatformAnalytics extends ConsumerWidget {
  const _PlatformAnalytics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(adminDashboardProvider);

    return dashboard.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: DottedProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ErrorView(
          error: err,
          onRetry: () => ref.invalidate(adminDashboardProvider),
        ),
      ),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Users by type'),
          _CategoryBars(items: d.usersByRole, colorFor: roleColor),
          const SectionHeader(title: 'Monthly active users'),
          _ActiveUsersCard(mau: d.monthlyActiveUsers, totalUsers: d.totalUsers),
          const SectionHeader(title: 'New registrations'),
          _RegistrationsTrend(series: d.registrationsByDay),
          const SectionHeader(title: 'Content volume'),
          _CategoryBars(items: d.contentVolume, colorFor: _contentColor),
          const SectionHeader(title: 'Business approval pipeline'),
          _CategoryBars(items: d.businessPipeline, colorFor: _pipelineColor),
        ],
      ),
    );
  }
}

Color _contentColor(String kind) => switch (kind) {
      'TEXT' => AppColors.button,
      'CODE' => const Color(0xFFA855F7),
      'VIDEO' => AppColors.danger,
      'BOUNTY' => AppColors.points,
      'OPPORTUNITY' => AppColors.accent,
      _ => AppColors.darkMuted,
    };

Color _pipelineColor(String status) => switch (status) {
      'PENDING' => AppColors.points,
      'ACTIVE' => AppColors.accent,
      'SUSPENDED' => AppColors.danger,
      'REJECTED' => AppColors.darkMuted,
      _ => AppColors.darkMuted,
    };

String _titleCase(String s) =>
    s.isEmpty ? s : '${s[0]}${s.substring(1).toLowerCase()}';

/// A ranked, proportional-width bar per category — same shape as the
/// student dashboard's skill bars (see `student_dashboard_screen.dart`),
/// duplicated privately here rather than shared since each screen owns
/// its own file per WORKPLAN.
class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.items, required this.colorFor});

  final List<CategoryCount> items;
  final Color Function(String label) colorFor;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    if (items.isEmpty || items.every((i) => i.count == 0)) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text('No data yet.', style: TextStyle(fontSize: 12.5, color: muted)),
      );
    }

    final maxCount =
        items.map((i) => i.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 31);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          for (final (i, item) in items.indexed) ...[
            _CategoryBarRow(item: item, maxCount: maxCount, color: colorFor(item.label)),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({required this.item, required this.maxCount, required this.color});

  final CategoryCount item;
  final int maxCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : item.count / maxCount;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            _titleCase(item.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 14,
              backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            '${item.count}',
            textAlign: TextAlign.right,
            style: monoStyle(size: 12, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Monthly active users shown as a proportion of everyone registered,
/// rather than a bare number — a progress bar is the "visual indicator"
/// §2.7 asks for when a full time series isn't the natural shape for a
/// single-value metric.
class _ActiveUsersCard extends StatelessWidget {
  const _ActiveUsersCard({required this.mau, required this.totalUsers});

  final int mau;
  final int totalUsers;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final pct = totalUsers == 0 ? 0.0 : (mau / totalUsers * 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$mau',
                style: monoStyle(size: 22, weight: FontWeight.w800, color: AppColors.accent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'of $totalUsers registered users signed in this month',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1),
              minHeight: 10,
              backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text('${pct.toStringAsFixed(0)}% monthly active', style: TextStyle(fontSize: 11.5, color: muted)),
        ],
      ),
    );
  }
}

/// A total plus a 30-day line — same shape as the student dashboard's
/// `_TrendCard`, duplicated privately for the same file-ownership reason
/// as [_CategoryBars].
class _RegistrationsTrend extends StatelessWidget {
  const _RegistrationsTrend({required this.series});

  final List<DailyMetric> series;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final total = series.fold<int>(0, (sum, d) => sum + d.value);
    final maxY = series.fold<double>(1, (m, d) => d.value > m ? d.value.toDouble() : m);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$total',
                style: monoStyle(size: 22, weight: FontWeight.w800, color: AppColors.button),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('new registrations, last 30 days', style: TextStyle(fontSize: 12, color: muted)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: series.isEmpty
                ? Center(
                    child: Text('No data yet', style: TextStyle(fontSize: 12, color: muted)),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (series.length - 1).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => Theme.of(context).colorScheme.surface,
                          getTooltipItems: (touched) => touched.map((spot) {
                            final day = series[spot.x.toInt()];
                            return LineTooltipItem(
                              '${day.value} · ${day.date.month}/${day.date.day}',
                              monoStyle(size: 11, weight: FontWeight.w700, color: AppColors.button),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < series.length; i++)
                              FlSpot(i.toDouble(), series[i].value.toDouble()),
                          ],
                          isCurved: false,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          color: AppColors.button,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.button.withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),
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
