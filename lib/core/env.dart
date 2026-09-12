/// Supabase credentials, supplied at build time.
///
/// Pass them with `--dart-define-from-file=env.json` (see `env.example.json`)
/// so the keys never live in source control. `flutter run` without them still
/// launches — the app shows a setup screen instead of failing at startup.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Stream A (AI assistant). Called directly from the client — see the
  /// doc comment on `AiRepository` for why, and the trade-off that implies.
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Offline UI walkthrough: `--dart-define=DEMO=true`.
  ///
  /// Runs the whole app against the canned data in `core/demo.dart` without
  /// initialising Supabase at all, so no project and no keys are needed. It
  /// bypasses row-level security by construction — never use it to show that
  /// an access rule works.
  static const demo = bool.fromEnvironment('DEMO');
}
