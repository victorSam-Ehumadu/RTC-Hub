import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase.dart';
import 'data/admin_repository.dart';
import 'data/ai_repository.dart';
import 'data/auth_repository.dart';
import 'data/opportunity_repository.dart';
import 'data/post_repository.dart';
import 'data/profile_repository.dart';
import 'data/social_repository.dart';
import 'data/storage_repository.dart';
import 'models/assistant.dart';
import 'models/opportunity.dart';
import 'models/post.dart';
import 'models/profile.dart';
import 'models/social.dart';

// ─── Repositories ─────────────────────────────────────────────

final authRepoProvider = Provider((_) => const AuthRepository());
final profileRepoProvider = Provider((_) => const ProfileRepository());
final postRepoProvider = Provider((_) => const PostRepository());
final connectionRepoProvider = Provider((_) => const ConnectionRepository());
final messageRepoProvider = Provider((_) => const MessageRepository());
final notificationRepoProvider = Provider((_) => const NotificationRepository());
final opportunityRepoProvider = Provider((_) => const OpportunityRepository());
final eventRepoProvider = Provider((_) => const EventRepository());
final adminRepoProvider = Provider((_) => const AdminRepository());
final analyticsRepoProvider = Provider((_) => const AnalyticsRepository());
final storageRepoProvider = Provider((_) => const StorageRepository());
final aiRepoProvider = Provider((_) => const AiRepository());

// ─── Session and profile ──────────────────────────────────────

/// Auth events straight from Supabase. Everything downstream keys off this,
/// so a sign-out anywhere tears down the whole authenticated tree.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepoProvider).changes;
});

/// True once a session exists. Read synchronously by the router.
final isSignedInProvider = Provider<bool>((ref) {
  ref.watch(authStateProvider);
  return db.auth.currentSession != null;
});

/// The signed-in user's own profile row.
///
/// Separate from the auth session because `role` and `status` live in
/// `profiles`, and the whole app gates on them: a PENDING business account has
/// a perfectly valid session but must not reach the main shell.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateProvider);
  if (db.auth.currentSession == null) return null;
  return ref.watch(authRepoProvider).currentProfile();
});

/// Convenience for widgets that only run inside the authenticated shell.
final meProvider = Provider<Profile?>((ref) {
  return ref.watch(myProfileProvider).valueOrNull;
});

/// Whether this user has been through the first-run tutorial yet.
/// `AppShell` watches this the same way it watches `myProfileProvider` — an
/// async read that a synchronous router `redirect` cannot do.
final onboardingProgressProvider =
    FutureProvider.autoDispose<OnboardingProgress>((ref) {
  return ref.watch(aiRepoProvider).onboardingProgress();
});

// ─── Feed and bounties ────────────────────────────────────────

enum FeedMode { following, discover }

final feedModeProvider = StateProvider<FeedMode>((_) => FeedMode.following);

final feedProvider = FutureProvider.autoDispose<List<Post>>((ref) async {
  final repo = ref.watch(postRepoProvider);
  final mode = ref.watch(feedModeProvider);
  return mode == FeedMode.following ? repo.feed() : repo.discover();
});

final bountyFacultyProvider = StateProvider<String?>((_) => null);

final bountiesProvider = FutureProvider.autoDispose<List<Post>>((ref) {
  return ref
      .watch(postRepoProvider)
      .bounties(faculty: ref.watch(bountyFacultyProvider));
});

final postProvider =
    FutureProvider.autoDispose.family<Post, String>((ref, postId) {
  return ref.watch(postRepoProvider).byId(postId);
});

final commentsProvider =
    FutureProvider.autoDispose.family<List<Comment>, String>((ref, postId) {
  return ref.watch(postRepoProvider).comments(postId);
});

final postsByAuthorProvider =
    FutureProvider.autoDispose.family<List<Post>, String>((ref, userId) {
  return ref.watch(postRepoProvider).byAuthor(userId);
});

// ─── Profiles ─────────────────────────────────────────────────

final profileProvider =
    FutureProvider.autoDispose.family<Profile, String>((ref, userId) {
  return ref.watch(profileRepoProvider).byId(userId);
});

final skillsProvider =
    FutureProvider.autoDispose.family<List<Skill>, String>((ref, userId) {
  return ref.watch(profileRepoProvider).skills(userId);
});

final experienceProvider = FutureProvider.autoDispose
    .family<List<WorkExperience>, String>((ref, userId) {
  return ref.watch(profileRepoProvider).experience(userId);
});

final logicPointsProvider =
    FutureProvider.autoDispose.family<int, String>((ref, userId) {
  return ref.watch(profileRepoProvider).logicPoints(userId);
});

final leaderboardProvider =
    FutureProvider.autoDispose<List<LeaderboardEntry>>((ref) {
  return ref.watch(profileRepoProvider).leaderboard();
});

final peopleSearchProvider = FutureProvider.autoDispose
    .family<List<Profile>, String>((ref, term) {
  return ref.watch(profileRepoProvider).search(term);
});

// ─── Connections ──────────────────────────────────────────────

final connectionsProvider = FutureProvider.autoDispose<List<Connection>>((ref) {
  return ref.watch(connectionRepoProvider).accepted();
});

final connectionRequestsProvider =
    FutureProvider.autoDispose<List<Connection>>((ref) {
  return ref.watch(connectionRepoProvider).incomingRequests();
});

final connectionWithProvider =
    FutureProvider.autoDispose.family<Connection?, String>((ref, userId) {
  return ref.watch(connectionRepoProvider).between(userId);
});

// ─── Messaging ────────────────────────────────────────────────

final conversationsProvider =
    FutureProvider.autoDispose<List<Conversation>>((ref) {
  return ref.watch(messageRepoProvider).conversations();
});

/// A live chat thread: the history, plus any realtime inserts that belong to
/// this conversation. Replaces the Socket.IO room the web client joined.
final threadProvider = StreamProvider.autoDispose
    .family<List<Message>, String>((ref, otherId) async* {
  final repo = ref.watch(messageRepoProvider);
  final me = requireUserId;

  final messages = await repo.thread(otherId);
  yield messages;

  final controller = StreamController<List<Message>>();
  final channel = repo.subscribe((message) {
    if (!message.inThread(me, otherId)) return;
    if (messages.any((m) => m.id == message.id)) return;
    messages.add(message);
    controller.add(List.of(messages));
  });

  ref.onDispose(() {
    db.removeChannel(channel);
    controller.close();
  });

  yield* controller.stream;
});

// ─── Notifications ────────────────────────────────────────────

/// The notification list, live: seeds from a query and then prepends
/// realtime inserts, mirroring [threadProvider]'s seed-then-append pattern.
///
/// Previously a one-shot [FutureProvider] — the badge count updated live
/// (see [unreadCountProvider] below) but the actual list only refreshed on a
/// manual pull-to-refresh or screen re-entry, because nothing ever appended
/// the realtime payload to it.
///
/// Watches [authStateProvider] for the same reason [unreadCountProvider]
/// does: without it, this would evaluate once at launch while the session is
/// still null and never re-run on sign-in.
final notificationsProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) async* {
  ref.watch(authStateProvider);

  if (db.auth.currentSession == null) {
    yield [];
    return;
  }
  final repo = ref.watch(notificationRepoProvider);

  final list = await repo.list();
  yield list;

  final controller = StreamController<List<AppNotification>>();
  final channel = repo.subscribe((n) {
    if (list.any((x) => x.id == n.id)) return;
    list.insert(0, n); // newest first
    controller.add(List.of(list));
  });

  ref.onDispose(() {
    db.removeChannel(channel);
    controller.close();
  });

  yield* controller.stream;
});

/// Unread badge count, derived from [notificationsProvider] so there's a
/// single realtime channel behind both rather than two independent ones.
final unreadCountProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull;
  return list?.where((n) => !n.read).length ?? 0;
});

// ─── Opportunities and events ─────────────────────────────────

final opportunitiesProvider =
    FutureProvider.autoDispose<List<Opportunity>>((ref) {
  return ref.watch(opportunityRepoProvider).browse();
});

final matchedOpportunitiesProvider =
    FutureProvider.autoDispose<List<Opportunity>>((ref) {
  return ref.watch(opportunityRepoProvider).matched();
});

final myOpportunitiesProvider =
    FutureProvider.autoDispose<List<Opportunity>>((ref) {
  return ref.watch(opportunityRepoProvider).mine();
});

final myApplicationsProvider =
    FutureProvider.autoDispose<List<Application>>((ref) {
  return ref.watch(opportunityRepoProvider).myApplications();
});

final applicationsForProvider = FutureProvider.autoDispose
    .family<List<Application>, String>((ref, opportunityId) {
  return ref.watch(opportunityRepoProvider).applicationsFor(opportunityId);
});

final upcomingEventsProvider =
    FutureProvider.autoDispose<List<CampusEvent>>((ref) {
  return ref.watch(eventRepoProvider).upcoming();
});

// ─── Admin and analytics ──────────────────────────────────────

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  return ref.watch(adminRepoProvider).stats();
});

final pendingUsersProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(adminRepoProvider).pendingUsers();
});

final pendingOpportunitiesProvider =
    FutureProvider.autoDispose<List<Opportunity>>((ref) {
  return ref.watch(adminRepoProvider).pendingOpportunities();
});

final openFlagsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(adminRepoProvider).openFlags();
});

/// §2.7's platform-level admin metrics — users by type, MAU, registrations
/// over time, content volume, business pipeline. Separate from
/// [adminStatsProvider] (the action-grid counts) so refreshing one doesn't
/// re-fetch the other.
final adminDashboardProvider =
    FutureProvider.autoDispose<AdminDashboard>((ref) {
  return ref.watch(adminRepoProvider).dashboard();
});

final studentStatsProvider =
    FutureProvider.autoDispose.family<StudentStats, String>((ref, userId) {
  return ref.watch(analyticsRepoProvider).forStudent(userId);
});

/// Platform-wide, not per-user — no `.family` needed.
final wantedSkillsProvider = FutureProvider.autoDispose<List<SkillCount>>((ref) {
  return ref.watch(analyticsRepoProvider).wantedSkills();
});

/// §2.7's business dashboard — applicant pipeline, engagement rate,
/// candidate skill distribution, applicant demographics, and company
/// profile reach. See `AnalyticsRepository.forBusiness`.
final businessStatsProvider =
    FutureProvider.autoDispose.family<BusinessStats, String>((ref, userId) {
  return ref.watch(analyticsRepoProvider).forBusiness(userId);
});

// ─── Theme ────────────────────────────────────────────────────

const _themeModePrefKey = 'theme_mode';

/// The user's light/dark preference from the settings drawer, persisted
/// across restarts. Defaults to dark — "the terminal look" main.dart used to
/// hardcode — until [ThemeModeController._restore] loads a saved choice.
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
        (_) => ThemeModeController());

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModePrefKey);
    if (saved != null && mounted) {
      state = ThemeMode.values.byName(saved);
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePrefKey, mode.name);
  }
}
