import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../onboarding/tutorial_screen.dart';

/// Bottom-nav frame, and the gate that decides whether an authenticated user
/// is actually allowed in.
///
/// A valid session is not enough: BUSINESS and ALUMNI accounts start as
/// PENDING and a moderator can SUSPEND anyone. The old Express `authenticate`
/// middleware rejected those on every request; here the check happens once,
/// around the whole authenticated tree.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);

    return profile.when(
      loading: () => const Scaffold(body: Loading()),
      error: (err, _) => Scaffold(
        body: ErrorView(
          error: err,
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
      ),
      data: (me) {
        if (me == null) {
          // Session exists but no profile row yet — the signup trigger is
          // mid-flight, or the account was deleted/created underneath us
          // (e.g. added straight in Supabase Auth instead of through the
          // app's signup, so handle_new_user() never ran). That first case
          // resolves itself in a second or two; the second one never will,
          // so this can't just spin forever with no way out.
          return Scaffold(
            body: _NoProfileView(
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
          );
        }
        if (!me.isActive) return AccountGateScreen(profile: me);

        // Stream A: first-run tutorial gate. Same pattern as the account
        // check above — this needs an async read (`onboarding_progress`),
        // so it lives here rather than in the router's synchronous
        // `redirect`. TutorialScreen chains into the AI onboarding chat
        // once finished; see its `_finish()`.
        final onboarding = ref.watch(onboardingProgressProvider);
        if (onboarding.isLoading) return const Scaffold(body: Loading());
        if (onboarding.valueOrNull?.tutorialComplete == false) {
          return const TutorialScreen();
        }

        return Scaffold(
          body: shell,
          bottomNavigationBar: _NavBar(shell: shell, isBusiness: me.isBusiness),
        );
      },
    );
  }
}

/// Shown in place of the endless spinner when a session exists but
/// `profiles` has no matching row. Auto-retries once (the signup trigger is
/// usually just mid-flight) and only then offers manual buttons, so a real
/// stuck state is always recoverable instead of a permanent blank spinner.
class _NoProfileView extends ConsumerStatefulWidget {
  const _NoProfileView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  ConsumerState<_NoProfileView> createState() => _NoProfileViewState();
}

class _NoProfileViewState extends ConsumerState<_NoProfileView> {
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showOptions = true);
      widget.onRetry();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showOptions) return const Loading();

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_search_outlined, size: 44),
              const SizedBox(height: 16),
              Text(
                "We can't find your profile",
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'Your account is signed in, but has no matching profile. '
                'This can happen right after signup — try again in a moment '
                '— or if the account was created outside the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.5,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  await ref.read(authRepoProvider).signOut();
                  if (context.mounted) context.go('/login');
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBar extends ConsumerWidget {
  const _NavBar({required this.shell, required this.isBusiness});

  final StatefulNavigationShell shell;
  final bool isBusiness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) =>
          shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.dynamic_feed_outlined),
          selectedIcon: Icon(Icons.dynamic_feed),
          label: 'Feed',
        ),
        const NavigationDestination(
          icon: Icon(Icons.bolt_outlined),
          selectedIcon: Icon(Icons.bolt),
          label: 'Bounties',
        ),
        NavigationDestination(
          icon: const Icon(Icons.work_outline),
          selectedIcon: const Icon(Icons.work),
          label: isBusiness ? 'Listings' : 'Jobs',
        ),
        const NavigationDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: 'Messages',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}

/// Shown to accounts that are not ACTIVE, in place of the whole app.
class AccountGateScreen extends ConsumerWidget {
  const AccountGateScreen({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = profile.status;
    final pending = status == 'PENDING';
    // Stream D: alumni are PENDING like a business, but nothing checks them
    // against anything — there's no institutional email to trust the way a
    // student's is trusted. This is the human-reviewed document step; see
    // docs/alumni-verification-design.md for why.
    final needsAlumniDoc = pending && profile.isAlumni;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pending ? Icons.hourglass_top : Icons.gpp_bad_outlined,
                  size: 56,
                  color: pending ? AppColors.points : AppColors.danger,
                ),
                const SizedBox(height: 22),
                Text(
                  pending ? 'Awaiting approval' : 'Account $status',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  needsAlumniDoc
                      ? 'A Richfield administrator is reviewing your '
                          'account. Uploading a document proving your '
                          'studies is optional, but helps them decide '
                          'faster.'
                      : pending
                          ? 'A Richfield administrator is reviewing your '
                              'registration. You will get a notification the '
                              'moment it is approved.'
                          : 'Your access has been withdrawn. Contact a '
                              'Richfield administrator if you think this is a '
                              'mistake.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.5,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                if (needsAlumniDoc) ...[
                  const SizedBox(height: 22),
                  _AlumniVerificationUpload(profile: profile),
                ],
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(myProfileProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check again'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    await ref.read(authRepoProvider).signOut();
                    if (context.mounted) context.go('/login');
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stream D: lets a PENDING alumnus upload the document an admin judges
/// their claimed student number and graduation year against. Uploading here
/// (rather than as a second step during signup) is deliberate — the router
/// redirects away from `/signup` the instant a session exists, so there is
/// no window to run a second step on that screen, and this also lets the
/// alumnus retry if their first upload was the wrong file.
class _AlumniVerificationUpload extends ConsumerStatefulWidget {
  const _AlumniVerificationUpload({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_AlumniVerificationUpload> createState() =>
      _AlumniVerificationUploadState();
}

class _AlumniVerificationUploadState
    extends ConsumerState<_AlumniVerificationUpload> {
  bool _busy = false;
  Object? _error;

  Future<void> _pickAndUpload() async {
    setState(() => _error = null);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      final url =
          await ref.read(storageRepoProvider).uploadVerification(File(path));
      await ref
          .read(profileRepoProvider)
          .update(widget.profile.copyWith(verificationPhotoUrl: url));
      ref.invalidate(myProfileProvider);
      if (mounted) {
        showMessage(context, 'Document submitted for review.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitted = (widget.profile.verificationPhotoUrl ?? '').isNotEmpty;

    return Column(
      children: [
        if (submitted)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'Document submitted',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorView(error: _error!),
        ],
        const SizedBox(height: 12),
        _busy
            ? const CircularProgressIndicator()
            : OutlinedButton.icon(
                onPressed: _pickAndUpload,
                icon: const Icon(Icons.upload_file, size: 18),
                label:
                    Text(submitted ? 'Replace document' : 'Upload document'),
              ),
      ],
    );
  }
}

/// White foreground used for text/icons that sit on top of [HubBanner] —
/// plain white reads on both the blue field and the red photo half of the
/// banner, regardless of the app's light/dark theme.
const hubBannerForeground = Colors.white;

/// Shadow that keeps [hubBannerForeground] text legible over the banner's
/// busier (photo) half.
const hubBannerTitleShadow = [Shadow(color: Colors.black87, blurRadius: 8)];

/// The Richfield banner image with a left-to-right dark scrim, sized to sit
/// behind an `AppBar` via `flexibleSpace`. Shared by [HubAppBar] and any
/// screen with its own `AppBar` that wants the same top-bar treatment (e.g.
/// [ProfileScreen]).
class HubBanner extends StatelessWidget {
  const HubBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/richfield-banner-logo.png',
          fit: BoxFit.cover,
          alignment: Alignment.centerLeft,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withValues(alpha: 0.8),
                Colors.black.withValues(alpha: 0.5),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared app bar for the tab screens: title on the left, notification bell
/// with a live unread badge on the right.
///
/// The Richfield banner sits behind the title and action icons on every tab
/// by default — `showBanner: false` opts a screen out if it ever needs the
/// plain bar back.
class HubAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const HubAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBanner = true,
  });

  final String title;
  final List<Widget>? actions;
  final bool showBanner;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final onBanner = showBanner ? hubBannerForeground : null;

    return AppBar(
      backgroundColor: showBanner ? Colors.transparent : null,
      elevation: 0,
      flexibleSpace: showBanner ? const HubBanner() : null,
      iconTheme: onBanner == null ? null : IconThemeData(color: onBanner),
      actionsIconTheme:
          onBanner == null ? null : IconThemeData(color: onBanner),
      title: Text(
        title,
        style: onBanner == null
            ? null
            : TextStyle(
                color: onBanner,
                fontWeight: FontWeight.w800,
                shadows: hubBannerTitleShadow,
              ),
      ),
      actions: [
        ...?actions,
        IconButton(
          onPressed: () => context.push('/notifications'),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_none, color: onBanner),
              if (unread > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
