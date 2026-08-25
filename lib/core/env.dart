/// Supabase credentials, supplied at build time.
///
/// Pass them with `--dart-define-from-file=env.json` (see `env.example.json`)
/// so the keys never live in source control. `flutter run` without them still
/// launches — the app shows a setup screen instead of failing at startup.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
