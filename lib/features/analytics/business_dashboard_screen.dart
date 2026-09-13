import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/analytics.dart';
import '../../providers.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';

/// The business dashboard — §2.7's list for this role, in order: applicant
/// pipeline per posted opportunity, engagement rate on listings, candidate
/// skill distribution across programmes, applicant breakdown by programme
/// and year, and overall reach for the company profile.
///
/// The brief insists the three dashboards be *distinct*, so this one is
/// built around the pipeline rather than around a trend line: a recruiter
/// opens it to answer "who applied to what, and are any of them worth
/// reading", which is a comparison across listings, not a time series.
class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);

    if (me != null && !me.isBusiness && !me.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Company dashboard')),
        body: const EmptyState(
          icon: Icons.business_outlined,
          title: 'Business accounts only',
          message: 'This dashboard reports on listings you have posted.',
        ),
      );
    }

    final data = ref.watch(businessDashboardProvider);
    final range = ref.watch(dashboardRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Company dashboard'),
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
          onRetry: () => ref.invalidate(businessDashboardProvider),
        ),
        data: (a) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(businessDashboardProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _Headline(analytics: a),

              const SectionHeader(title: 'Applicant pipeline'),
              ChartCard(
                title: 'Per listing',
                subtitle: a.pipeline.isEmpty
                    ? 'Post an opportunity to start seeing applicants'
                    : 'Applied, shortlisted and rejected side by side',
                height: 240,
                child: PipelineBars(rows: a.pipeline),
              ),
              if (a.pipeline.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PipelineTable(rows: a.pipeline),
              ],

              const SectionHeader(title: 'Listing engagement'),
              ChartCard(
                title: 'Applications received',
                subtitle: 'Last $range days',
                child: TimeSeriesChart(points: a.applicationsByDay, slot: 1),
              ),

              const SectionHeader(title: 'Candidate skills'),
              ChartWithTable(
                title: 'Most common skills among applicants',
                subtitle: 'Across everyone who applied to your listings',
                points: a.topSkills,
                labelHeading: 'Skill',
                chart: CategoryBars(points: a.topSkills, slot: 2),
              ),

              const SectionHeader(title: 'Applicants by programme'),
              ChartWithTable(
                title: 'Which courses apply to you',
                points: a.byProgramme,
                labelHeading: 'Programme',
                chart: CategoryBars(points: a.byProgramme, slot: 3),
              ),

              const SectionHeader(title: 'Applicants by year of study'),
              ChartWithTable(
                title: 'How far through their studies',
                points: a.byYear,
                labelHeading: 'Year',
                chart: CategoryBars(points: a.byYear, slot: 4),
              ),

              const SectionHeader(title: 'Applicants by faculty'),
              ChartWithTable(
                title: 'IT and Business split',
                subtitle: 'Reflects which cohorts you chose to recruit from',
                points: a.byFaculty,
                labelHeading: 'Faculty',
                chart: CategoryBars(points: a.byFaculty, slot: 5),
              ),

              const SectionHeader(title: 'Company profile reach'),
              ChartCard(
                title: 'Profile views',
                subtitle: 'Last $range days',
                child: TimeSeriesChart(points: a.profileViewsByDay, slot: 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.analytics});

  final BusinessAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final a = analytics;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Applicants',
                value: '${a.totalApplicants}',
                icon: Icons.people_outline,
                colour: AppColors.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Live listings',
                value: '${a.activeListings}',
                icon: Icons.work_outline,
                colour: AppColors.success,
                footnote: a.pendingListings > 0
                    ? '${a.pendingListings} awaiting approval'
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Per listing',
                value: a.applicationsPerListing.toStringAsFixed(1),
                icon: Icons.equalizer,
                colour: AppColors.points,
                footnote: 'applications each',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The pipeline as rows, under the chart.
///
/// A recruiter needs the listing *name* to act on this, and a bar chart with
/// eight truncated labels is not something you can work from — the chart
/// shows the shape, the table gives the detail.
class _PipelineTable extends StatelessWidget {
  const _PipelineTable({required this.rows});

  final List<PipelineRow> rows;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          rows[i].status,
                          style: monoStyle(size: 10, color: muted),
                        ),
                      ],
                    ),
                  ),
                  _Pill(
                    value: rows[i].applicants,
                    label: 'applied',
                    colour: AppColors.accent,
                  ),
                  const SizedBox(width: 6),
                  _Pill(
                    value: rows[i].shortlisted,
                    label: 'shortlisted',
                    colour: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  _Pill(
                    value: rows[i].rejected,
                    label: 'declined',
                    colour: AppColors.danger,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.value,
    required this.label,
    required this.colour,
  });

  final int value;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        constraints: const BoxConstraints(minWidth: 30),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: value == 0 ? 0.06 : 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: monoStyle(
            size: 12,
            weight: FontWeight.w700,
            color: value == 0 ? colour.withValues(alpha: 0.45) : colour,
          ),
        ),
      ),
    );
  }
}
