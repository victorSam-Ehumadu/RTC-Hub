import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/analytics.dart';
import '../../providers.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';

/// The administrator dashboard — §2.7 in full.
///
/// The brief is explicit that raw numbers do not count: *"Raw numbers
/// displayed without visualisation will not satisfy this requirement."* The
/// admin console's six stat tiles were exactly that, so every metric here
/// that has a shape gets plotted, and the tiles that remain are headline
/// figures sitting above a chart rather than standing in for one.
///
/// Everything comes from one `admin_dashboard()` call. Assembling it from
/// the client would be thirteen round-trips to paint one screen.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);

    // The RPC itself refuses a non-admin, so this is courtesy rather than
    // the boundary — but an error screen is a poor way to learn you are in
    // the wrong place.
    if (me != null && !me.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Platform dashboard')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Administrators only',
        ),
      );
    }

    final data = ref.watch(adminDashboardProvider);
    final range = ref.watch(dashboardRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform dashboard'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Range',
            initialValue: range,
            onSelected: (days) =>
                ref.read(dashboardRangeProvider.notifier).state = days,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Last 7 days')),
              PopupMenuItem(value: 30, child: Text('Last 30 days')),
              PopupMenuItem(value: 90, child: Text('Last 90 days')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('$range days', style: monoStyle(size: 12)),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(
          error: err,
          onRetry: () => ref.invalidate(adminDashboardProvider),
        ),
        data: (a) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminDashboardProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _Headline(analytics: a, range: range),

              const SectionHeader(title: 'Registrations over time'),
              ChartCard(
                title: 'New accounts',
                subtitle: 'Last $range days',
                child: TimeSeriesChart(points: a.registrationsByDay),
              ),

              const SectionHeader(title: 'Users by type'),
              ChartWithTable(
                title: 'Accounts per role',
                subtitle: '${a.totalUsers} total',
                points: a.usersByType,
                labelHeading: 'Role',
                chart: CategoryBars(points: a.usersByType, slot: 1),
              ),

              const SectionHeader(title: 'Accounts by status'),
              ChartWithTable(
                title: 'Approval states',
                subtitle: 'PENDING accounts are waiting on you',
                points: a.usersByStatus,
                labelHeading: 'Status',
                chart: CategoryBars(points: a.usersByStatus, slot: 2),
              ),

              const SectionHeader(title: 'Content volume'),
              ChartCard(
                title: 'Posts and comments created',
                subtitle: 'Last $range days',
                child: TimeSeriesChart(points: a.contentByDay, slot: 3),
              ),
              const SizedBox(height: 10),
              _CountGrid(
                counts: a.contentVolume,
                empty: 'Nothing posted yet.',
              ),

              const SectionHeader(title: 'Business approval pipeline'),
              _CountGrid(
                counts: a.businessPipeline,
                empty: 'No business accounts yet.',
                colourFor: _statusColour,
              ),

              const SectionHeader(title: 'Opportunity pipeline'),
              _CountGrid(
                counts: a.opportunityPipeline,
                empty: 'No listings yet.',
                colourFor: _statusColour,
              ),

              const SectionHeader(title: 'Moderation'),
              _FlagSplit(open: a.flaggedOpen, resolved: a.flaggedResolved),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColour(String key) => switch (key.toUpperCase()) {
        'ACTIVE' => AppColors.success,
        'PENDING' => AppColors.points,
        'SUSPENDED' || 'REJECTED' => AppColors.danger,
        _ => AppColors.darkMuted,
      };
}

/// The two numbers an administrator opens this screen to see.
class _Headline extends StatelessWidget {
  const _Headline({required this.analytics, required this.range});

  final AdminAnalytics analytics;
  final int range;

  @override
  Widget build(BuildContext context) {
    final pending = analytics.usersByStatus
        .where((p) => p.label.toUpperCase() == 'PENDING')
        .fold<int>(0, (sum, p) => sum + p.value.toInt());

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Total users',
            value: '${analytics.totalUsers}',
            icon: Icons.people_outline,
            colour: roleColor('STUDENT'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: 'Active this month',
            value: '${analytics.monthlyActiveUsers}',
            icon: Icons.trending_up,
            colour: AppColors.success,
            footnote: 'signed in within 30 days',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: 'Awaiting review',
            value: '$pending',
            icon: Icons.hourglass_top,
            colour: pending > 0 ? AppColors.points : AppColors.darkMuted,
            footnote: pending > 0 ? 'needs action' : 'all clear',
          ),
        ),
      ],
    );
  }
}

/// A labelled count set — content volume, approval pipelines.
///
/// These are genuinely categorical totals with no time dimension, so a chart
/// would be decoration. They sit *beside* charts rather than instead of
/// them, which is the distinction §2.7 is drawing.
class _CountGrid extends StatelessWidget {
  const _CountGrid({
    required this.counts,
    required this.empty,
    this.colourFor,
  });

  final Map<String, int> counts;
  final String empty;
  final Color Function(String key)? colourFor;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          empty,
          style: TextStyle(
            fontSize: 12.5,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final e in entries)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 32 - 20) / 3,
            child: StatTile(
              label: _pretty(e.key),
              value: '${e.value}',
              colour: colourFor?.call(e.key),
            ),
          ),
      ],
    );
  }

  static String _pretty(String key) {
    final spaced = key.replaceAll('_', ' ').toLowerCase();
    return spaced.isEmpty
        ? key
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}

/// Open versus resolved flags, as a proportion rather than two numbers —
/// "12 open" means something different against 15 resolved than against 400.
class _FlagSplit extends StatelessWidget {
  const _FlagSplit({required this.open, required this.resolved});

  final int open;
  final int resolved;

  @override
  Widget build(BuildContext context) {
    final total = open + resolved;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Nothing has been reported.',
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
      );
    }

    final openShare = open / total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$open open',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: open > 0 ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ),
                Text('$resolved resolved',
                    style: TextStyle(fontSize: 12.5, color: muted)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Expanded(
                    flex: (openShare * 1000).round().clamp(0, 1000),
                    child: Container(height: 10, color: AppColors.danger),
                  ),
                  Expanded(
                    flex: ((1 - openShare) * 1000).round().clamp(0, 1000),
                    child: Container(
                      height: 10,
                      color: AppColors.success.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              open == 0
                  ? 'Queue is clear.'
                  : '${(openShare * 100).toStringAsFixed(0)}% of all reports '
                      'are still waiting.',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
