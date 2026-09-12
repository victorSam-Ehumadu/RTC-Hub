import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/code_runner.dart';
import '../providers.dart';

/// Syntax-highlighted snippet attached to a CODE or BOUNTY post.
///
/// This is the "technical signal" the whole product is built around, so code
/// gets a distinct frame rather than being dropped into body text.
class CodeBlock extends ConsumerStatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language,
    this.maxLines,
    this.runnable = true,
  });

  final String code;
  final String? language;
  final int? maxLines;

  /// Feed cards pass false: a Run button on every card in a scrolling list
  /// invites accidental taps and would hammer a shared rate limit. Running
  /// happens on the post detail screen, where the output has room.
  final bool runnable;

  @override
  ConsumerState<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends ConsumerState<CodeBlock> {
  CodeResult? _result;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
    });
    final result = await ref.read(codeRunnerProvider).run(
          code: widget.code,
          language: widget.language ?? '',
        );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code;
    final language = widget.language;
    final maxLines = widget.maxLines;
    final canRun = widget.runnable && CodeRunner.canRun(language);
    final reason = CodeRunner.unavailableReason(language);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = Theme.of(context).colorScheme.outline;

    // flutter_highlight throws on an unknown language id, so fall back to
    // plaintext for anything we did not offer in the composer.
    final lang =
        (language != null && language.isNotEmpty) ? language : 'plaintext';

    var body = code.trimRight();
    var truncated = false;
    if (maxLines != null) {
      final lines = body.split('\n');
      if (lines.length > maxLines) {
        body = lines.take(maxLines).join('\n');
        truncated = true;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0B1220) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
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
                Icon(Icons.terminal, size: 13, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  lang,
                  style: monoStyle(size: 11, color: AppColors.accent),
                ),
                const Spacer(),
                if (canRun) ...[
                  _RunButton(running: _running, onRun: _run),
                  const SizedBox(width: 4),
                ] else if (widget.runnable && reason != null) ...[
                  Tooltip(
                    message: reason,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(
                      Icons.not_interested,
                      size: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(content: Text('Snippet copied')),
                      );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_all_outlined,
                      size: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: HighlightView(
              body,
              language: lang,
              theme: dark ? atomOneDarkTheme : atomOneLightTheme,
              textStyle: monoStyle(size: 12.5, weight: FontWeight.w400),
            ),
          ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 10),
              child: Text(
                '…',
                style: monoStyle(
                  size: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
          if (_result != null) _OutputPanel(result: _result!),
        ],
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.running, required this.onRun});

  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: running ? null : onRun,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (running)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: AppColors.accent,
                ),
              )
            else
              Icon(Icons.play_arrow_rounded, size: 15, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              running ? 'Running' : 'Run',
              style: monoStyle(size: 11, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// stdout and stderr from a run, kept visually distinct from the source
/// above it — this is a terminal, not more code.
class _OutputPanel extends StatelessWidget {
  const _OutputPanel({required this.result});

  final CodeResult result;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outline;
    final ok = result.ok;
    final statusColour = result.transportError != null
        ? AppColors.points
        : (ok ? AppColors.success : AppColors.danger);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 13,
                color: statusColour,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  result.summary,
                  style: monoStyle(size: 11, color: statusColour),
                ),
              ),
            ],
          ),
          if (result.stdout.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              result.stdout,
              style: monoStyle(size: 12, weight: FontWeight.w400),
            ),
          ],
          if (result.stderr.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              result.stderr,
              style: monoStyle(
                size: 12,
                weight: FontWeight.w400,
                color: AppColors.danger,
              ),
            ),
          ],
          if (!result.hasOutput && result.transportError == null) ...[
            const SizedBox(height: 6),
            Text(
              'No output.',
              style: monoStyle(
                size: 11.5,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
