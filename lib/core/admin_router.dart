import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_login_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/feed/post_detail_screen.dart';
import '../providers.dart';
import 'supabase.dart';

/// Router for the standalone administrator portal (`main_admin.dart`) —
/// deliberately its own small route table, not an addition to
/// [routerProvider] in `router.dart`.
///
/// Per the hackathon brief (§2.1), "administrators do not use the same
/// registration flow as other user types", so this table has no `/signup`
/// and no path back into the feed, bounties, messages, or any other
/// student/business/alumni screen — [AdminLoginScreen] and [AdminScreen] are
/// the entire app. `/post/:id` is kept only so the Flags tab's "View" button
/// still works.
///
/// The redirect only checks that a session exists, same as the main router —
/// it must run synchronously. Whether that session belongs to an admin is
/// decided twice over: [AdminLoginScreen] signs a non-admin straight back out
/// before this redirect ever sees a session to act on, and [AdminScreen]
/// re-checks independently (backed by `is_admin()` in RLS) in case either of
/// those is ever bypassed.
final adminRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = db.auth.currentSession != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn && !atLogin) return '/login';
      if (signedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const AdminLoginScreen()),
      GoRoute(path: '/', builder: (_, _) => const AdminScreen()),
      GoRoute(
        path: '/post/:id',
        builder: (_, state) =>
            PostDetailScreen(postId: state.pathParameters['id']!),
      ),
    ],
  );
});
