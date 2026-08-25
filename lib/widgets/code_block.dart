import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';

import '../core/theme.dart';

/// Syntax-highlighted snippet attached to a CODE or BOUNTY post.
///
/// This is the "technical signal" the whole product is built around, so code
/// gets a distinct frame rather than being dropped into body text.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language,
    this.maxLines,
  });

  final String code;
  final String? language;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = Theme.of(context).colorScheme.outline;

    // flutter_highlight throws on an unknown language id, so fall back to
    // plaintext for anything we did not offer in the composer.
    final lang = (language != null && language!.isNotEmpty) ? language! : 'plaintext';

    var body = code.trimRight();
    var truncated = false;
    if (maxLines != null) {
      final lines = body.split('\n');
      if (lines.length > maxLines!) {
        body = lines.take(maxLines!).join('\n');
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
        ],
      ),
    );
  }
}
