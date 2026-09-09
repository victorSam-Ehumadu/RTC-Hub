import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

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
        if (!me.isActive) return AccountGateScreen(status: me.status);

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
  const AccountGateScreen({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = status == 'PENDING';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
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
                  pending
                      ? 'A Richfield administrator is reviewing your '
                          'registration. You will get a notification the moment '
                          'it is approved.'
                      : 'Your access has been withdrawn. Contact a Richfield '
                          'administrator if you think this is a mistake.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.5,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
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

/// Shared app bar for the tab screens: title on the left, notification bell
/// with a live unread badge on the right.
class HubAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const HubAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return AppBar(
      title: Text(title),
      actions: [
        ...?actions,
        IconButton(
          onPressed: () => context.push('/notifications'),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none),
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
