import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/admin_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// The business dashboard — §2.7's mandatory list, in full: applicant
/// pipeline per listing, engagement rate on listings, candidate skill
/// distribution across programmes, applicant demographics by programme and
/// year, and reach/visibility for the company profile.
///
/// Reachable from "Your listings" (see `_BusinessView` in
/// opportunities_screen.dart), not the profile tab — a business account
/// lives on the opportunities tab, and that keeps this feature's entry
/// point out of `profile_screen.dart`, which belongs to a different stream.
class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key});

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
    final stats = ref.watch(businessStatsProvider(userId));

    return stats.when(
      loading: () => const Loading(),
      error: (err, _) => ErrorView(
        error: err,
        onRetry: () => ref.invalidate(businessStatsProvider(userId)),
      ),
      data: (s) {
        final totalApplicants =
            s.pipeline.fold<int>(0, (sum, p) => sum + p.applicants);

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(businessStatsProvider(userId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              const SectionHeader(title: 'Applicant pipeline'),
              _PipelineBars(pipeline: s.pipeline),
              const SectionHeader(title: 'Engagement rate on listings'),
              _EngagementRows(pipeline: s.pipeline),
              const SectionHeader(title: 'Candidate skills, across programmes'),
              _CandidateSkillBars(
                items: s.candidateSkills,
                emptyText: 'No applicant has listed a skill yet — this '
                    'fills in as people apply.',
              ),
              const SectionHeader(title: 'Applicants by programme & year'),
              _DemographicsBars(items: s.applicantDemographics),
              if (totalApplicants > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The two sections above only count applicants who '
                    'have made their profile visible to businesses — a '
                    'smaller number than the pipeline total is expected, '
                    'not a bug.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ),
              const SectionHeader(title: 'Company profile reach'),
              _TrendCard(
                series: s.viewsByDay,
                total: s.profileViews,
                color: AppColors.accent,
                caption: 'profile views, last 30 days',
              ),
            ],
          ),
        );
      },
    );
  }
}

Color _statusColor(String status) => switch (status) {
      'ACTIVE' => AppColors.accent,
      'PENDING' => AppColors.points,
      'REJECTED' => AppColors.danger,
      _ => AppColors.darkMuted,
    };

/// §2.7's "total applicant pipeline per posted opportunity" — one bar per
/// listing, any status, coloured by [_statusColor] so a PENDING listing
/// awaiting approval reads differently from a live one.
class _PipelineBars extends StatelessWidget {
  const _PipelineBars({required this.pipeline});

  final List<ListingPipeline> pipeline;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    if (pipeline.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text(
          'Post a listing to start seeing applicants here.',
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
      );
    }

    final maxCount = pipeline
        .map((p) => p.applicants)
        .fold<int>(0, (m, v) => v > m ? v : m)
        .clamp(1, 1 << 31);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          for (final (i, listing) in pipeline.indexed) ...[
            _PipelineRow(listing: listing, maxCount: maxCount),
            if (i != pipeline.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({required this.listing, required this.maxCount});

  final ListingPipeline listing;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : listing.applicants / maxCount;
    final color = _statusColor(listing.status);

    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            listing.title,
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
            '${listing.applicants}',
            textAlign: TextAlign.right,
            style: monoStyle(size: 12, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// §2.7's "engagement rate on job listings" — applicants ÷ reach per
/// listing, as a proportional bar. A PENDING/REJECTED listing (or any
/// listing nobody has viewed yet) shows "Awaiting views" rather than a
/// literal 0%, since [ListingPipeline.engagementRate] is null exactly when
/// there is no denominator to divide by — see migration 0013.
class _EngagementRows extends StatelessWidget {
  const _EngagementRows({required this.pipeline});

  final List<ListingPipeline> pipeline;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    if (pipeline.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text('No listings yet.', style: TextStyle(fontSize: 12.5, color: muted)),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          for (final (i, listing) in pipeline.indexed) ...[
            _EngagementRow(listing: listing),
            if (i != pipeline.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _EngagementRow extends StatelessWidget {
  const _EngagementRow({required this.listing});

  final ListingPipeline listing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final rate = listing.engagementRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                listing.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              rate == null ? 'Awaiting views' : '${rate.round()}%',
              style: rate == null
                  ? TextStyle(fontSize: 11.5, color: muted)
                  : monoStyle(size: 12.5, weight: FontWeight.w700, color: AppColors.button),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ((rate ?? 0) / 100).clamp(0, 1),
            minHeight: 8,
            backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
            valueColor: const AlwaysStoppedAnimation(AppColors.button),
          ),
        ),
      ],
    );
  }
}

/// §2.7's "candidate skill distribution across Richfield programmes" —
/// ranked bars over the caller's own applicant pool (see migration 0013's
/// header for why it's scoped that way), each skill annotated with the
/// programme it's most common in among those applicants.
class _CandidateSkillBars extends StatelessWidget {
  const _CandidateSkillBars({required this.items, required this.emptyText});

  final List<CandidateSkill> items;
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
            _CandidateSkillRow(item: item, maxCount: maxCount),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CandidateSkillRow extends StatelessWidget {
  const _CandidateSkillRow({required this.item, required this.maxCount});

  final CandidateSkill item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final fraction = maxCount == 0 ? 0.0 : item.count / maxCount;

    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.skill,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              if (item.topCourse != null)
                Text(
                  item.topCourse!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: muted),
                ),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 14,
              backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation(AppColors.points),
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

/// §2.7's "demographic breakdown of applicants by programme and year of
/// study" — one bar per (course, academic year) combination. Same shape as
/// the admin dashboard's `_CategoryBars`, duplicated privately here rather
/// than shared, per this file's own ownership (see `admin_screen.dart` and
/// `student_dashboard_screen.dart`, which do the same).
class _DemographicsBars extends StatelessWidget {
  const _DemographicsBars({required this.items});

  final List<CategoryCount> items;

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
        child: Text(
          'No applicants yet — this fills in once people apply.',
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
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
            _DemographicsRow(item: item, maxCount: maxCount),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _DemographicsRow extends StatelessWidget {
  const _DemographicsRow({required this.item, required this.maxCount});

  final CategoryCount item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : item.count / maxCount;

    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            item.label,
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
              valueColor: const AlwaysStoppedAnimation(AppColors.button),
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

/// §2.7's "overall reach and visibility statistics for the company
/// profile" — a total plus a 30-day line, same shape as the student and
/// admin dashboards' own `_TrendCard`, duplicated privately for the same
/// file-ownership reason as [_DemographicsBars].
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
