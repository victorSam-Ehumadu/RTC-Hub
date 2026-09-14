import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/demo.dart';
import 'core/env.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  dotenv.load(fileName: ".env");
  runApp(RtcHubApp());

  timeago.setLocaleMessages('en_short', timeago.EnShortMessages());

  // Demo mode never contacts Supabase, so it must short-circuit before both
  // the credential check and Supabase.initialize.
  if (Env.demo) {
    runApp(ProviderScope(overrides: demoOverrides, child: const RtcHubApp()));
    return;
  }

  // Without credentials there is nothing to connect to, so show setup
  // instructions rather than crashing inside Supabase.initialize.
  if (!Env.isConfigured) {
    runApp(const _SetupNeededApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: RtcHubApp()));
}

class RtcHubApp extends ConsumerWidget {
  const RtcHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'RTC Hub',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark, // the terminal look is the default
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown when SUPABASE_URL / SUPABASE_ANON_KEY were not passed at build time.
class _SetupNeededApp extends StatelessWidget {
  const _SetupNeededApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTC Hub',
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
                const Icon(
                  Icons.settings_ethernet,
                  size: 48,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 20),
                Text(
                  'Supabase is not configured',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
                    'flutter run --dart-define-from-file=env.json',
                    style: monoStyle(size: 13, color: AppColors.accent),
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
