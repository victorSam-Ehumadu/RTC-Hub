import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../data/errors.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// The student dashboard — §2.7's mandatory list, in full: profile views
/// over time, connection growth, post engagement, completeness vs.
/// programme peers, and most-searched skills (split into what businesses
/// ask for and what people actually search, per product decision — see
/// migration 0007). Reachable from the profile screen's "Your numbers" row.
class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(meProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Your dashboard')),
      body: userId == null ? const Loading() : _Body(userId: userId),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(studentStatsProvider(userId));

    return stats.when(
      loading: () => const Loading(),
      error: (err, _) => ErrorView(
        error: err,
        onRetry: () => ref.invalidate(studentStatsProvider(userId)),
      ),
      data: (s) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(studentStatsProvider(userId));
          ref.invalidate(skillSignalsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            const SectionHeader(title: 'Profile views'),
            _TrendCard(
              series: s.viewsByDay,
              total: s.profileViews,
              color: AppColors.accent,
              caption: 'views, last 30 days',
            ),
            const SectionHeader(title: 'Connection growth'),
            _TrendCard(
              series: s.connectionsByDay,
              total: s.newConnections,
              color: AppColors.button,
              caption: 'new connections, last 30 days',
            ),
            const SectionHeader(title: 'Post engagement'),
            _TrendCard(
              series: s.engagementByDay,
              total: s.postReactions,
              color: AppColors.points,
              caption: 'reactions received, last 30 days',
            ),
            const SectionHeader(title: 'Completeness vs. programme peers'),
            _CompletenessComparison(
              mine: s.myCompleteness,
              avg: s.programmeAvgCompleteness,
              peers: s.programmePeerCount,
            ),
            const _SkillSignalsSection(),
          ],
        ),
      ),
    );
  }
}

class _SkillSignalsSection extends ConsumerWidget {
  const _SkillSignalsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signals = ref.watch(skillSignalsProvider);

    return signals.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: DottedProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(describeError(err)),
      ),
      data: (signals) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Skills businesses want'),
          _SkillBars(
            items: signals.wantedByBusinesses,
            color: AppColors.button,
            emptyText: 'No active listings yet — check back once businesses '
                'start posting opportunities.',
          ),
          const SectionHeader(title: 'Most-searched skills'),
          _SkillBars(
            items: signals.mostSearched,
            color: AppColors.points,
            emptyText: 'Nobody has searched for a catalog skill yet.',
          ),
        ],
      ),
    );
  }
}

/// A total plus a 30-day line, used for the three §2.7 time-series metrics.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.series,
    required this.total,
    required this.color,
    required this.caption,
  });

  final List<DailyMetric> series;
  final int total;
  final Color color;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final maxY = series.fold<double>(
      1,
      (m, d) => d.value > m ? d.value.toDouble() : m,
    );

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
                style: monoStyle(size: 22, weight: FontWeight.w800, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(caption, style: TextStyle(fontSize: 12, color: muted)),
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
                              monoStyle(size: 11, weight: FontWeight.w700, color: color),
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
                          color: color,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: color.withValues(alpha: 0.12),
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

/// Two proportional bars — you vs. your programme's average — rather than a
/// single number, so a viewer can place themselves without doing the
/// subtraction themselves.
class _CompletenessComparison extends StatelessWidget {
  const _CompletenessComparison({
    required this.mine,
    required this.avg,
    required this.peers,
  });

  final int mine;
  final double avg;
  final int peers;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

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
          _CompletenessRow(label: 'You', value: mine.toDouble(), color: AppColors.accent),
          const SizedBox(height: 12),
          _CompletenessRow(
            label: 'Programme average',
            value: avg,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 10),
          Text(
            peers > 0
                ? 'Compared with $peers classmate${peers == 1 ? '' : 's'} in your programme.'
                : 'Nobody else in your programme is visible yet — this fills '
                    'in as classmates join.',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
        ],
      ),
    );
  }
}

class _CompletenessRow extends StatelessWidget {
  const _CompletenessRow({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Text(
              '${value.round()}%',
              style: monoStyle(size: 12.5, weight: FontWeight.w700, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0, 100) / 100,
            minHeight: 8,
            backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// A ranked, proportional-width bar per skill — used for both skill charts.
/// One flat hue per card (there is only one series here), length carries the
/// magnitude, and the count is direct-labeled rather than relying on a
/// shared axis nobody would read precisely on a phone screen.
class _SkillBars extends StatelessWidget {
  const _SkillBars({required this.items, required this.color, required this.emptyText});

  final List<SkillCount> items;
  final Color color;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text(emptyText, style: TextStyle(fontSize: 12.5, color: muted)),
      );
    }

    final maxCount = items.map((i) => i.count).reduce((a, b) => a > b ? a : b);

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
            _SkillBarRow(item: item, maxCount: maxCount, color: color),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SkillBarRow extends StatelessWidget {
  const _SkillBarRow({required this.item, required this.maxCount, required this.color});

  final SkillCount item;
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
            item.skill,
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
          width: 26,
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
