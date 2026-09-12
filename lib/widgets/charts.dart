import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/analytics.dart';

/// Chart colours.
///
/// Deliberately **not** the theme accent and deliberately not [roleColor].
/// Two reasons:
///
///   * A series colour has to stay put when the user switches palette —
///     identity that moves with the theme is not identity.
///   * `roleColor`'s STUDENT blue and ALUMNI violet are ΔE 0.9 apart under
///     deuteranopia. On a legend they are fine, because the label carries the
///     meaning; as adjacent bars they are the same bar twice for a red-green
///     colourblind reader. Validated slots are used instead.
///
/// These eight hues and both sets of steps come from a palette validated with
/// the data-viz validator against this app's own surfaces (#111827 dark,
/// #FFFFFF light): lightness band, chroma floor, adjacent-pair CVD separation,
/// normal-vision floor and contrast all pass in both modes.
///
/// On the light surface aqua and yellow fall below 3:1, which obligates
/// "relief" — so every bar chart here ships a visible value label rather than
/// relying on the bar alone. That is a requirement, not a flourish.
class ChartPalette {
  const ChartPalette._();

  static const _light = <Color>[
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF4A3AA7), // violet
    Color(0xFFE34948), // red
  ];

  static const _dark = <Color>[
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
  ];

  /// Slot [index] for the current brightness.
  ///
  /// Never cycles past the end: a ninth series is a signal to fold the tail
  /// into "Other" or facet, not to invent a hue. Callers here cap their
  /// series well before that.
  static Color slot(BuildContext context, int index) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ramp = dark ? _dark : _light;
    return ramp[index.clamp(0, ramp.length - 1)];
  }

  /// Status steps. Fixed, never themed, and deliberately outside the
  /// categorical lightness band so a status colour never impersonates a
  /// series. Always paired with a label — never colour alone.
  static const good = Color(0xFF0CA30C);
  static const warning = Color(0xFFFAB219);
  static const critical = Color(0xFFD03B3B);
}

/// A titled chart container, so every chart on a dashboard has the same frame.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.height = 200,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 11.5, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
                ...?trailing == null ? null : [trailing!],
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(height: height, child: child),
          ],
        ),
      ),
    );
  }
}

/// A single measure over time.
///
/// One series, so no legend — the card title names it. 2px line, no grid, no
/// border: the shape is the information and everything else is furniture.
class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({super.key, required this.points, this.slot = 0});

  final List<DataPoint> points;
  final int slot;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const _NotEnoughData();

    final colour = ChartPalette.slot(context, slot);
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final maxY = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: 0,
        // A flat-zero series would otherwise draw on the axis with no room;
        // 4 gives the line somewhere to sit.
        maxY: (maxY == 0 ? 4 : maxY * 1.25).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY == 0 ? 1 : maxY / 2).toDouble(),
          getDrawingHorizontalLine: (_) => FlLine(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (maxY == 0 ? 1 : maxY / 2).toDouble(),
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(fontSize: 9.5, color: muted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              // First, middle and last only. A label per day is unreadable at
              // phone width and collides before it informs.
              interval: (points.length / 2).clamp(1, points.length).toDouble(),
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    points[i].shortDate,
                    style: TextStyle(fontSize: 9.5, color: muted),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${points[spot.x.toInt()].shortDate}\n'
                  '${spot.y.toInt()}',
                  TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value.toDouble()),
            ],
            isCurved: true,
            curveSmoothness: 0.22,
            barWidth: 2,
            color: colour,
            // Markers on a 30-point daily series are noise; the line carries
            // the shape and the tooltip carries the value.
            dotData: FlDotData(show: points.length <= 10),
            belowBarData: BarAreaData(
              show: true,
              color: colour.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Magnitude by category, as horizontal rows.
///
/// Horizontal rather than vertical because the labels are course names and
/// skill names, which do not fit under a vertical bar at phone width. Each row
/// carries its value as text — which is also the "relief" the light-mode
/// contrast warning requires.
class CategoryBars extends StatelessWidget {
  const CategoryBars({
    super.key,
    required this.points,
    this.slot = 0,
    this.maxRows = 8,
  });

  final List<DataPoint> points;
  final int slot;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const _NotEnoughData();

    final shown = points.take(maxRows).toList();
    final colour = ChartPalette.slot(context, slot);
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final max = shown.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final point in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    point.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    // 4px rounded data-end, anchored to the baseline.
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                    child: Container(
                      height: 14,
                      alignment: Alignment.centerLeft,
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.25),
                      child: FractionallySizedBox(
                        widthFactor: max == 0
                            ? 0
                            : (point.value / max).toDouble().clamp(0.02, 1),
                        child: Container(color: colour),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // The direct label. Text ink, not the series colour.
                SizedBox(
                  width: 34,
                  child: Text(
                    '${point.value.toInt()}',
                    textAlign: TextAlign.right,
                    style: monoStyle(size: 11.5, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A composition of three states per row — the applicant pipeline.
///
/// Status colours, so a legend with labels is mandatory: colour alone never
/// carries the meaning. A 2px gap separates adjacent fills so the boundary is
/// a boundary rather than a colour change.
class PipelineBars extends StatelessWidget {
  const PipelineBars({super.key, required this.rows});

  final List<PipelineRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _NotEnoughData();

    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final max = rows
        .map((r) => r.applicants)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PipelineLegend(),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            row.applicants == 1
                                ? '1 applicant'
                                : '${row.applicants} applicants',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 14,
                        child: row.applicants == 0
                            ? Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  'No applicants yet',
                                  style: TextStyle(fontSize: 9.5, color: muted),
                                ),
                              )
                            : Row(
                                children: [
                                  for (final part in [
                                    (row.shortlisted, ChartPalette.good),
                                    (row.pending, ChartPalette.warning),
                                    (row.rejected, ChartPalette.critical),
                                  ])
                                    if (part.$1 > 0) ...[
                                      Expanded(
                                        flex: part.$1,
                                        child: Container(color: part.$2),
                                      ),
                                      // The 2px surface gap between fills.
                                      const SizedBox(width: 2),
                                    ],
                                  // Remaining width keeps rows comparable:
                                  // a listing with 2 of 10 applicants reads as
                                  // short, not as full.
                                  if (row.applicants < max)
                                    Expanded(
                                      flex: max - row.applicants,
                                      child: const SizedBox.shrink(),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PipelineLegend extends StatelessWidget {
  const _PipelineLegend();

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final entry in const [
          ('Shortlisted', ChartPalette.good, Icons.check_circle_outline),
          ('Awaiting decision', ChartPalette.warning, Icons.schedule),
          ('Not taken forward', ChartPalette.critical, Icons.cancel_outlined),
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon as well as swatch: a status colour never carries the
              // meaning on its own.
              Icon(entry.$3, size: 12, color: entry.$2),
              const SizedBox(width: 5),
              Text(entry.$1, style: TextStyle(fontSize: 10.5, color: muted)),
            ],
          ),
      ],
    );
  }
}

/// A single headline number. Not every measure deserves a plot — "847 active
/// users" is a fact, not a shape.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.colour,
    this.footnote,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? colour;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final accent = colour ?? ChartPalette.slot(context, 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted, height: 1.25),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: monoStyle(size: 22, weight: FontWeight.w700)),
            if (footnote != null)
              Text(
                footnote!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// A breakdown rendered as a table.
///
/// Every chart on these dashboards has one available. It is the accessibility
/// fallback and it is also the fastest way to read exact numbers, which is
/// often what an administrator actually wants.
class DataTableView extends StatelessWidget {
  const DataTableView({
    super.key,
    required this.points,
    this.labelHeading = 'Category',
    this.valueHeading = 'Count',
  });

  final List<DataPoint> points;
  final String labelHeading;
  final String valueHeading;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 34,
        columnSpacing: 24,
        columns: [
          DataColumn(
            label: Text(labelHeading,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          DataColumn(
            numeric: true,
            label: Text(valueHeading,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ],
        rows: [
          for (final point in points)
            DataRow(cells: [
              DataCell(Text(point.label,
                  style: const TextStyle(fontSize: 11.5))),
              DataCell(Text('${point.value.toInt()}',
                  style: monoStyle(size: 11.5))),
            ]),
        ],
      ),
    );
  }
}

/// A chart that can be flipped to its table. Satisfies the "a table view
/// exists" rule without doubling every dashboard's markup.
class ChartWithTable extends StatefulWidget {
  const ChartWithTable({
    super.key,
    required this.title,
    required this.points,
    required this.chart,
    this.subtitle,
    this.height = 200,
    this.labelHeading = 'Category',
  });

  final String title;
  final String? subtitle;
  final List<DataPoint> points;
  final Widget chart;
  final double height;
  final String labelHeading;

  @override
  State<ChartWithTable> createState() => _ChartWithTableState();
}

class _ChartWithTableState extends State<ChartWithTable> {
  bool _asTable = false;

  @override
  Widget build(BuildContext context) {
    return ChartCard(
      title: widget.title,
      subtitle: widget.subtitle,
      height: widget.height,
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 17,
        tooltip: _asTable ? 'Show chart' : 'Show numbers',
        icon: Icon(_asTable ? Icons.show_chart : Icons.table_rows_outlined),
        onPressed: () => setState(() => _asTable = !_asTable),
      ),
      child: _asTable
          ? DataTableView(
              points: widget.points,
              labelHeading: widget.labelHeading,
            )
          : widget.chart,
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData();

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          'Not enough data yet.',
          style: TextStyle(
            fontSize: 12,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
}
