import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/sheet.dart';
import '../providers.dart';
import 'common.dart';

/// A spreadsheet attached to a post or a submission.
///
/// This is a *preview*, not an editor. The app deliberately does not evaluate
/// formulas — Excel and Sheets recalculate on open, so the real work happens
/// there, and a half-correct formula engine here would only produce numbers
/// that disagree with the ones the user sees when they open the file. Formula
/// cells are shown verbatim and marked, so it is obvious which values are
/// computed and which were typed.
class SheetPreview extends ConsumerStatefulWidget {
  const SheetPreview({
    super.key,
    required this.sheet,
    this.title = 'sheet',
    this.maxRows = 6,
  });

  final SheetDoc sheet;
  final String title;

  /// Feed cards stay short; the detail screen passes a larger number.
  final int maxRows;

  @override
  ConsumerState<SheetPreview> createState() => _SheetPreviewState();
}

class _SheetPreviewState extends ConsumerState<SheetPreview> {
  bool _busy = false;

  /// Writes the .xlsx and hands it to whatever opens spreadsheets.
  Future<void> _handOff({required bool share}) async {
    setState(() => _busy = true);
    try {
      final docs = ref.read(documentServiceProvider);
      final file = await docs.writeSheet(widget.sheet, title: widget.title);

      if (share) {
        await docs.share(file, subject: widget.title);
      } else {
        final problem = await docs.openExternally(file);
        // No spreadsheet app installed is a normal outcome, not an error —
        // fall back to the share sheet rather than dead-ending.
        if (problem != null && mounted) {
          showMessage(context, problem);
          await docs.share(file, subject: widget.title);
        }
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.sheet;
    final border = Theme.of(context).colorScheme.outline;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final accent = facultyColor('BUSINESS');

    final shown = sheet.rows.take(widget.maxRows).toList();
    final hidden = sheet.rowCount - shown.length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Icon(Icons.grid_on, size: 13, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    sheet.name ?? 'spreadsheet',
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(size: 11, color: accent),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    sheet.summary,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: muted),
                  ),
                ),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
              ],
            ),
          ),

          if (sheet.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Empty sheet.',
                  style: TextStyle(fontSize: 12.5, color: muted)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 34,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 34,
                horizontalMargin: 12,
                columnSpacing: 22,
                dividerThickness: 0.5,
                columns: [
                  for (final column in sheet.columns)
                    DataColumn(
                      label: Text(
                        column,
                        style: monoStyle(size: 11.5, weight: FontWeight.w700),
                      ),
                    ),
                ],
                rows: [
                  for (final row in shown)
                    DataRow(
                      cells: [
                        for (var c = 0; c < sheet.columnCount; c++)
                          DataCell(_Cell(
                            value: c < row.length ? row[c] : '',
                            accent: accent,
                          )),
                      ],
                    ),
                ],
              ),
            ),

          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                '+$hidden more ${hidden == 1 ? 'row' : 'rows'}',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _handOff(share: false),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in Excel'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _handOff(share: true),
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One cell. Formulas are shown as written and tinted, so a reader can tell
/// at a glance which numbers the file computes for itself.
class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.accent});

  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final formula = SheetDoc.isFormula(value);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Text(
        value,
        overflow: TextOverflow.ellipsis,
        style: monoStyle(
          size: 11.5,
          weight: FontWeight.w400,
          color: formula ? accent : null,
        ),
      ),
    );
  }
}

/// Open/Share for a code snippet.
///
/// Sits next to the Run button rather than replacing it: running tells you
/// whether the code works, opening it elsewhere lets you actually work on it.
/// On a stock Android install nothing claims a .java file, which is why Share
/// is offered with equal weight rather than hidden behind Open.
class CodeHandoff extends ConsumerStatefulWidget {
  const CodeHandoff({
    super.key,
    required this.code,
    this.language,
    this.title = 'snippet',
  });

  final String code;
  final String? language;
  final String title;

  @override
  ConsumerState<CodeHandoff> createState() => _CodeHandoffState();
}

class _CodeHandoffState extends ConsumerState<CodeHandoff> {
  bool _busy = false;

  Future<void> _go({required bool share}) async {
    setState(() => _busy = true);
    try {
      final docs = ref.read(documentServiceProvider);
      final File file = await docs.writeSnippet(
        code: widget.code,
        language: widget.language,
        title: widget.title,
      );
      if (share) {
        await docs.share(file, subject: widget.title);
      } else {
        final problem = await docs.openExternally(file);
        if (problem != null && mounted) {
          showMessage(context, problem);
          await docs.share(file, subject: widget.title);
        }
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: _busy ? null : () => _go(share: false),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open in editor'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _go(share: true),
          icon: const Icon(Icons.ios_share, size: 16),
          label: const Text('Share'),
        ),
      ],
    );
  }
}
