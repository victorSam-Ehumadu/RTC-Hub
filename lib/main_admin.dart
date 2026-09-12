import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/admin_router.dart';
import 'core/env.dart';
import 'core/theme.dart';

/// Entry point for the standalone administrator portal — a separate build
/// target from `main.dart`, run with:
///
/// ```
/// flutter run -d chrome -t lib/main_admin.dart --dart-define-from-file=env.json
/// flutter build web -t lib/main_admin.dart --dart-define-from-file=env.json
/// ```
///
/// It talks to the same Supabase project as the mobile app — there is no
/// second backend, per CLAUDE.md — but it is its own app: its own login
/// screen with no sign-up link, its own tiny route table (`core/admin_router
/// .dart`), and no import of `core/router.dart` or any student/business/
/// alumni screen. That separation, not a different auth backend, is what
/// satisfies the brief's "administrators do not use the same registration
/// flow as other user types".
///
/// Deliberately no `Env.demo` branch here. Demo mode bypasses RLS by
/// construction, and this build exists specifically to demonstrate that
/// non-admins are turned away — the one thing demo mode can never prove.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _AdminSetupNeededApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: RtcHubAdminApp()));
}

class RtcHubAdminApp extends ConsumerWidget {
  const RtcHubAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'RTC Hub Admin',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(adminRouterProvider),
    );
  }
}

/// Shown when SUPABASE_URL / SUPABASE_ANON_KEY were not passed at build time
/// — mirrors `main.dart`'s `_SetupNeededApp`, rebranded for this portal.
class _AdminSetupNeededApp extends StatelessWidget {
  const _AdminSetupNeededApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTC Hub Admin',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.settings_ethernet,
                    size: 48, color: AppColors.danger),
                const SizedBox(height: 20),
                Text(
                  'Supabase is not configured',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Copy env.example.json to env.json, fill in your project URL '
                  'and anon key, then run:',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: SelectableText(
                    'flutter run -d chrome -t lib/main_admin.dart '
                    '--dart-define-from-file=env.json',
                    style: monoStyle(size: 13, color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
