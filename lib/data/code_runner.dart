import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Executes a snippet attached to a post.
///
/// This is the one place in the app that talks to something other than
/// Supabase, and it is deliberate. Running a peer's code is the point of an
/// IT-faculty bounty — "does your fix actually work" is the question being
/// asked — but arbitrary code cannot run in the Flutter isolate: no sandbox,
/// no timeout, and nothing to stop `while(true){}` freezing the phone. It has
/// to execute somewhere disposable.
///
/// **Why Paiza and not Piston.** Piston was the obvious pick and is what most
/// write-ups recommend, but its public API went whitelist-only on
/// 2026-02-15 and now answers every request with a link to the whitelist
/// form. Wandbox was the next candidate: its API is up, but its execution
/// backend currently fails every submission with `Failed to get uid`. Paiza's
/// guest tier needs no key, no account and no card, and was verified working
/// for python3, java, javascript, typescript, php, cpp, csharp and mysql
/// before this was written.
///
/// The trade-offs are real and worth stating: the guest tier is rate limited
/// and shared, it needs a working connection, and it is someone else's free
/// service. Swapping to a self-hosted Piston or a keyed Judge0 means changing
/// [_base] and the two request builders, not a rewrite.
class CodeRunner {
  const CodeRunner();

  static const _base = 'https://api.paiza.io/runners';
  static const _apiKey = 'guest';

  /// Wall-clock ceiling for one HTTP call. Paiza's own limits stop runaway
  /// code long before this; the timeout is for a dead connection, which on
  /// campus wifi is the likelier failure.
  static const _httpTimeout = Duration(seconds: 20);

  /// Total budget for the poll loop. Compiled languages routinely take five
  /// or six seconds on a cold runner.
  static const _pollBudget = Duration(seconds: 35);

  /// Our composer's language ids mapped to Paiza runtimes.
  ///
  /// `dart` is deliberately absent: Paiza does not offer it, and pretending
  /// otherwise would put a Run button on Flutter snippets that can only ever
  /// fail. `html` and `css` have no stdout to show.
  static const _languages = <String, String>{
    'python': 'python3',
    'java': 'java',
    'javascript': 'javascript',
    'typescript': 'typescript',
    'php': 'php',
    'cpp': 'cpp',
    'csharp': 'csharp',
    'sql': 'mysql',
  };

  static bool canRun(String? language) =>
      language != null && _languages.containsKey(language);

  /// Why a language the composer offers has no Run button, for the UI to
  /// explain rather than silently hiding the control.
  static String? unavailableReason(String? language) {
    if (language == null || language.isEmpty) return null;
    if (_languages.containsKey(language)) return null;
    return switch (language) {
      'dart' => 'Dart snippets cannot be run here yet — no sandbox offers it.',
      'html' || 'css' => 'There is nothing to execute in $language.',
      _ => '$language cannot be run here.',
    };
  }

  /// Java will not compile a bare statement list, and a student answering a
  /// bounty will paste a fragment without a class. Wrap it when a class is
  /// obviously missing rather than showing them a compiler error about code
  /// they did not write.
  static String _prepare(String code, String runtime) {
    if (runtime != 'java') return code;
    if (RegExp(r'\bclass\s+\w+').hasMatch(code)) return code;

    final indented = code.split('\n').map((l) => '        $l').join('\n');
    return 'public class Main {\n'
        '    public static void main(String[] args) throws Exception {\n'
        '$indented\n'
        '    }\n'
        '}';
  }

  Future<CodeResult> run({
    required String code,
    required String language,
    String stdin = '',
  }) async {
    final runtime = _languages[language];
    if (runtime == null) {
      return CodeResult.failure(
        unavailableReason(language) ?? '$language cannot be run here.',
      );
    }
    if (code.trim().isEmpty) {
      return CodeResult.failure('There is no code to run.');
    }

    final started = DateTime.now();
    try {
      // 1. Submit.
      final created = await http.post(
        Uri.parse('$_base/create'),
        body: {
          'source_code': _prepare(code, runtime),
          'language': runtime,
          'input': stdin,
          'api_key': _apiKey,
        },
      ).timeout(_httpTimeout);

      if (created.statusCode == 429) {
        return CodeResult.failure(
          'The code runner is busy. Give it a few seconds and try again.',
        );
      }
      if (created.statusCode != 200) {
        return CodeResult.failure(
          'The code runner returned ${created.statusCode}.',
        );
      }

      final job = jsonDecode(created.body) as Map<String, dynamic>;
      final id = job['id'] as String?;
      if (id == null) {
        return CodeResult.failure(
          (job['error'] as String?) ?? 'The code runner rejected the snippet.',
        );
      }

      // 2. Poll. Paiza is asynchronous: create returns immediately and the
      //    result only exists once status flips to completed.
      var waited = Duration.zero;
      var interval = const Duration(milliseconds: 400);
      var completed = false;

      while (waited < _pollBudget) {
        await Future<void>.delayed(interval);
        waited += interval;
        // Back off gently so a slow compile does not mean 80 requests.
        interval = Duration(
          milliseconds: (interval.inMilliseconds * 1.4).round().clamp(400, 2500),
        );

        final status = await http
            .get(Uri.parse('$_base/get_status?id=$id&api_key=$_apiKey'))
            .timeout(_httpTimeout);
        if (status.statusCode != 200) continue;

        final decoded = jsonDecode(status.body) as Map<String, dynamic>;
        if (decoded['status'] == 'completed') {
          completed = true;
          break;
        }
      }

      if (!completed) {
        return CodeResult.failure(
          'The code runner did not finish in time. Try again in a moment.',
        );
      }

      // 3. Collect.
      final details = await http
          .get(Uri.parse('$_base/get_details?id=$id&api_key=$_apiKey'))
          .timeout(_httpTimeout);
      if (details.statusCode != 200) {
        return CodeResult.failure(
          'Could not read the result (${details.statusCode}).',
        );
      }

      final d = jsonDecode(details.body) as Map<String, dynamic>;
      final elapsed = DateTime.now().difference(started);

      // A compile failure arrives with build_result set and no run output,
      // which is the common case for Java, C++ and C#. It has to reach the
      // user rather than being reported as an empty success.
      final buildResult = d['build_result'] as String?;
      if (buildResult != null && buildResult != 'success') {
        return CodeResult(
          stdout: ((d['build_stdout'] ?? '') as String).trimRight(),
          stderr: ((d['build_stderr'] ?? '') as String).trimRight(),
          exitCode: int.tryParse('${d['build_exit_code']}') ?? 1,
          duration: elapsed,
          compileFailed: true,
        );
      }

      final result = d['result'] as String?;
      return CodeResult(
        stdout: ((d['stdout'] ?? '') as String).trimRight(),
        stderr: ((d['stderr'] ?? '') as String).trimRight(),
        exitCode: int.tryParse('${d['exit_code']}') ?? 0,
        duration: elapsed,
        timedOut: result == 'timeout',
        runtimeSeconds: double.tryParse('${d['time']}'),
      );
    } on TimeoutException {
      return CodeResult.failure(
        'The code runner did not answer in time. Check your connection.',
      );
    } catch (error) {
      return CodeResult.failure('Could not reach the code runner. $error');
    }
  }
}

class CodeResult {
  const CodeResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.duration,
    this.compileFailed = false,
    this.timedOut = false,
    this.transportError,
    this.runtimeSeconds,
  });

  factory CodeResult.failure(String message) =>
      CodeResult(stdout: '', stderr: '', exitCode: -1, transportError: message);

  final String stdout;
  final String stderr;
  final int exitCode;

  /// Round-trip including queueing, which is what the user actually waited.
  final Duration? duration;

  /// What the sandbox billed the program itself, when it reports it.
  final double? runtimeSeconds;

  final bool compileFailed;
  final bool timedOut;

  /// Set when the run never happened — offline, rate limited, bad response.
  /// Distinct from [stderr], which means the code itself complained.
  final String? transportError;

  bool get ok =>
      transportError == null && exitCode == 0 && !timedOut && !compileFailed;

  bool get hasOutput => stdout.isNotEmpty || stderr.isNotEmpty;

  String get summary {
    if (transportError != null) return transportError!;
    if (timedOut) return 'Killed — is there an infinite loop?';
    if (compileFailed) return 'Compile error';
    if (exitCode != 0) return 'Exited with code $exitCode';
    if (runtimeSeconds != null) return 'Finished in ${runtimeSeconds}s';
    final ms = duration?.inMilliseconds;
    return ms == null ? 'Finished' : 'Finished in ${ms}ms';
  }
}
