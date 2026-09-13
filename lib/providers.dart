import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase.dart';
import 'data/admin_repository.dart';
import 'data/ai_repository.dart';
import 'data/code_runner.dart';
import 'data/document_service.dart';
import 'data/engagement_repository.dart';
import 'data/auth_repository.dart';
import 'data/opportunity_repository.dart';
import 'data/portfolio_repository.dart';
import 'data/post_repository.dart';
import 'data/profile_repository.dart';
import 'data/social_repository.dart';
import 'data/storage_repository.dart';
import 'data/verification_repository.dart';
import 'data/video_service.dart';
import 'models/assistant.dart';
import 'models/opportunity.dart';
import 'models/post.dart';
import 'models/analytics.dart';
import 'models/portfolio.dart';
import 'models/profile.dart';
import 'models/verification.dart';
import 'models/recommendation.dart';
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
final engagementRepoProvider =
    Provider((_) => const EngagementRepository());

/// Sandboxed execution for snippets. Not a Supabase repository — see
/// `data/code_runner.dart` for why it is a separate service.
final codeRunnerProvider = Provider((_) => const CodeRunner());

/// Export to .xlsx / source files and hand off to Excel, Sheets or an
/// editor. See `data/document_service.dart`.
final documentServiceProvider = Provider((_) => const DocumentService());

/// Transcoding and thumbnail generation for short-form video (§2.8).
final videoServiceProvider = Provider((_) => const VideoService());

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

/// One section of a bounty thread. Keyed by `"<postId>|<kind>"` because a
/// Riverpod family takes a single argument and records are not const-able as
/// a family key across Riverpod 2.
final commentSectionProvider =
    FutureProvider.autoDispose.family<List<Comment>, String>((ref, key) {
  final parts = key.split('|');
  return ref.watch(postRepoProvider).comments(parts.first, kind: parts.last);
});

final postsByAuthorProvider =
    FutureProvider.autoDispose.family<List<Post>, String>((ref, userId) {
  return ref.watch(postRepoProvider).byAuthor(userId);
});

// ─── Profiles ─────────────────────────────────────────────────

/// A profile by id. Null when the caller may not see it — a hidden profile
/// is a state to explain, not an error to throw.
///
/// For *someone else's* profile prefer [viewedProfileProvider], which routes
/// through `profile_for_viewer()` so per-section visibility is applied before
/// the data leaves the server. This one returns the whole row and is for your
/// own profile, or where only identity fields are needed.
final profileProvider =
    FutureProvider.autoDispose.family<Profile?, String>((ref, userId) {
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
    .family<List<Profile>, String>((ref, term) async {
  // The picker rebuilds on every keystroke, so without this a five-letter
  // name is five round-trips and five sets of results racing to render.
  if (term.trim().isNotEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
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

final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationRepoProvider).list();
});

/// Unread badge count, kept live so a notification arriving mid-session bumps
/// the bell without a manual refresh.
///
/// Watches [authStateProvider] so it re-runs on sign-in — without that it would
/// evaluate once at launch while the session is still null and stay at zero for
/// the rest of the run.
final unreadCountProvider = StreamProvider<int>((ref) async* {
  ref.watch(authStateProvider);

  if (db.auth.currentSession == null) {
    yield 0;
    return;
  }
  final repo = ref.watch(notificationRepoProvider);

  yield await repo.unreadCount();

  final controller = StreamController<int>();
  // Re-count rather than incrementing a local tally: marking notifications
  // read elsewhere in the app has to be able to take the badge *down*, and a
  // counter that only ever goes up cannot.
  final channel = repo.subscribe((_) async {
    if (controller.isClosed) return;
    controller.add(await repo.unreadCount());
  });

  ref.onDispose(() {
    db.removeChannel(channel);
    controller.close();
  });

  yield* controller.stream;
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

/// Past and future, for the administrator's management tab.
final allEventsProvider =
    FutureProvider.autoDispose<List<CampusEvent>>((ref) {
  return ref.watch(eventRepoProvider).all();
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

final studentStatsProvider =
    FutureProvider.autoDispose.family<StudentStats, String>((ref, userId) {
  return ref.watch(analyticsRepoProvider).forStudent(userId);
});

/// Platform-wide, not per-user — no `.family` needed.
final wantedSkillsProvider = FutureProvider.autoDispose<List<SkillCount>>((ref) {
  return ref.watch(analyticsRepoProvider).wantedSkills();
});

// ─── Recommendations, saves, search (§2.3 + basics) ───────────

final recommendationsProvider = FutureProvider.autoDispose
    .family<List<Recommendation>, String>((ref, userId) {
  return ref.watch(engagementRepoProvider).forSubject(userId);
});

/// Recommendations waiting on the signed-in user to approve. Drives the
/// badge on the profile's own recommendations section.
final pendingRecommendationsProvider =
    FutureProvider.autoDispose<List<Recommendation>>((ref) {
  return ref.watch(engagementRepoProvider).pendingForMe();
});

final writtenRecommendationsProvider =
    FutureProvider.autoDispose<List<Recommendation>>((ref) {
  return ref.watch(engagementRepoProvider).written();
});

final savedIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  return ref.watch(engagementRepoProvider).savedIds();
});

final savedPostsProvider = FutureProvider.autoDispose<List<Post>>((ref) {
  return ref.watch(engagementRepoProvider).savedPosts();
});

final savedOpportunitiesProvider =
    FutureProvider.autoDispose<List<Opportunity>>((ref) {
  return ref.watch(engagementRepoProvider).savedOpportunities();
});

/// The current search term. A provider rather than widget state so the
/// results provider can key off it and debounce naturally through Riverpod's
/// own rebuild coalescing.
final searchTermProvider = StateProvider.autoDispose<String>((_) => '');

final searchResultsProvider =
    FutureProvider.autoDispose<List<SearchHit>>((ref) async {
  final term = ref.watch(searchTermProvider).trim();
  if (term.length < 2) return const [];

  // Let a fast typist finish the word before we ask the database.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  return ref.watch(engagementRepoProvider).search(term);
});

final suggestedConnectionsProvider =
    FutureProvider.autoDispose<List<ConnectionSuggestion>>((ref) {
  return ref.watch(engagementRepoProvider).suggestions();
});

/// Someone else's profile with hidden sections already stripped server-side.
/// Use this rather than [profileProvider] for anyone who is not the signed-in
/// user — see `profile_for_viewer()` in migration 0011.
final viewedProfileProvider =
    FutureProvider.autoDispose.family<Profile?, String>((ref, userId) {
  return ref.watch(engagementRepoProvider).profileForViewer(userId);
});

// ─── Dashboards (§2.7) ────────────────────────────────────────

final adminAnalyticsRepoProvider =
    Provider((_) => const AdminAnalyticsRepository());
final businessAnalyticsRepoProvider =
    Provider((_) => const BusinessAnalyticsRepository());

/// How far back the dashboards look. Shared by both so the range selector
/// reads the same on either screen.
final dashboardRangeProvider = StateProvider.autoDispose<int>((_) => 30);

final adminDashboardProvider =
    FutureProvider.autoDispose<AdminAnalytics>((ref) {
  return ref
      .watch(adminAnalyticsRepoProvider)
      .dashboard(days: ref.watch(dashboardRangeProvider));
});

final businessDashboardProvider =
    FutureProvider.autoDispose<BusinessAnalytics>((ref) {
  return ref
      .watch(businessAnalyticsRepoProvider)
      .dashboard(days: ref.watch(dashboardRangeProvider));
});

// ─── Portfolio sections (§2.3) and career pathways (§2.5) ─────

final portfolioRepoProvider = Provider((_) => const PortfolioRepository());

/// Keyed `"<userId>|<kind>"` — a Riverpod family takes one argument, and the
/// same convention is already used by commentSectionProvider.
final portfolioItemsProvider = FutureProvider.autoDispose
    .family<List<PortfolioItem>, String>((ref, key) {
  final parts = key.split('|');
  return ref.watch(portfolioRepoProvider).items(parts.first, kind: parts.last);
});

final credentialsProvider = FutureProvider.autoDispose
    .family<List<Credential>, String>((ref, key) {
  final parts = key.split('|');
  return ref
      .watch(portfolioRepoProvider)
      .credentials(parts.first, kind: parts.last);
});

final highlightsProvider = FutureProvider.autoDispose
    .family<List<ProfileHighlight>, String>((ref, key) {
  final parts = key.split('|');
  return ref
      .watch(portfolioRepoProvider)
      .highlights(parts.first, kind: parts.last);
});

/// Which programme the pathway explorer is showing. Null means the caller's
/// own, which is what the screen opens on.
final pathwayCourseProvider = StateProvider.autoDispose<String?>((_) => null);

final careerPathwayProvider =
    FutureProvider.autoDispose<List<CareerPathwayEntry>>((ref) {
  return ref
      .watch(portfolioRepoProvider)
      .pathway(course: ref.watch(pathwayCourseProvider));
});

final pathwayCoursesProvider =
    FutureProvider.autoDispose<List<({String course, int alumni})>>((ref) {
  return ref.watch(portfolioRepoProvider).pathwayCourses();
});

// ─── Alumni identity verification (§2.1) ──────────────────────

final verificationRepoProvider =
    Provider((_) => const VerificationRepository());

/// The signed-in user's own submission. Null means they have not started;
/// the account gate keys off this to decide between the form and the
/// waiting room.
final myVerificationProvider =
    FutureProvider.autoDispose<AlumniVerification?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(verificationRepoProvider).mine();
});

final alumniQueueStatusProvider =
    StateProvider.autoDispose<String>((_) => 'PENDING');

final alumniQueueProvider =
    FutureProvider.autoDispose<List<AlumniVerification>>((ref) {
  return ref
      .watch(verificationRepoProvider)
      .queue(status: ref.watch(alumniQueueStatusProvider));
});
