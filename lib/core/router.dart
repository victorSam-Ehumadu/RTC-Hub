import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_screen.dart';
import '../features/analytics/student_dashboard_screen.dart';
import '../features/assistant/assistant_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/bounty/bounty_screen.dart';
import '../features/events/events_screen.dart';
import '../features/feed/create_post_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/feed/post_detail_screen.dart';
import '../features/messages/chat_screen.dart';
import '../features/messages/conversations_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/cv_skills_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/tutorial_screen.dart';
import '../features/opportunities/create_opportunity_screen.dart';
import '../features/opportunities/opportunities_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/leaderboard_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/app_shell.dart';
import '../providers.dart';
import 'env.dart';
import 'supabase.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Router for the whole app.
///
/// The redirect below is deliberately session-only: it can run synchronously,
/// which a `redirect` must. Whether the *profile* is allowed into the app —
/// PENDING business accounts, suspended users — is decided by [AppShell],
/// because that needs an async read of the `profiles` row.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/feed',
    refreshListenable: refresh,
    redirect: (context, state) {
      // Env.demo first: in demo mode Supabase is never initialised, so
      // reading db.auth here would throw.
      final signedIn = Env.demo || db.auth.currentSession != null;
      final atAuth = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';

      if (!signedIn && !atAuth) return '/login';
      if (signedIn && atAuth) return '/feed';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),

      // Bottom-nav tabs. IndexedStack keeps each tab's scroll position and
      // loaded data when switching, which matters on the feed.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/feed', builder: (_, _) => const FeedScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/bounties', builder: (_, _) => const BountyScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/opportunities',
              builder: (_, _) => const OpportunitiesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/messages',
              builder: (_, _) => const ConversationsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/me',
              builder: (_, _) => const ProfileScreen(userId: null),
            ),
          ]),
        ],
      ),

      // Pushed over the shell, so the bottom bar is hidden.
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/post/:id',
        builder: (_, state) =>
            PostDetailScreen(postId: state.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/user/:id',
        builder: (_, state) =>
            ProfileScreen(userId: state.pathParameters['id']),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(otherId: state.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/compose',
        builder: (_, state) =>
            CreatePostScreen(asBounty: state.uri.queryParameters['bounty'] == '1'),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/edit-profile',
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/events',
        builder: (_, _) => const EventsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/leaderboard',
        builder: (_, _) => const LeaderboardScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/post-opportunity',
        builder: (_, _) => const CreateOpportunityScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/admin',
        builder: (_, _) => const AdminScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/dashboard',
        builder: (_, _) => const StudentDashboardScreen(),
      ),

      // Stream A (AI assistant). /onboarding and /tutorial are pushed by
      // AppShell on first login (see app_shell.dart); /assistant and
      // /cv-skills are reachable any time afterwards.
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/tutorial',
        builder: (_, _) => const TutorialScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/onboarding',
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/assistant',
        builder: (_, _) => const AssistantScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/cv-skills',
        builder: (_, _) => const CvSkillsScreen(),
      ),
    ],
  );
});
