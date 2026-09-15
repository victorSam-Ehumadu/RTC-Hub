import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../settings/change_password_dialog.dart';
import '../settings/delete_account_flow.dart';

/// The hamburger-triggered quick-access settings panel: Home, Dashboard,
/// Edit profile, light/dark toggle, Change password, Delete account, Log
/// out. Inlined directly in the Drawer rather than pushed as its own
/// /settings route — simpler for a "quick access" panel, and trivial to
/// promote to a pushed screen later if the list grows.
///
/// Attach this as `drawer:` on every top-level tab Scaffold (the ones built
/// with [HubAppBar]) and on ProfileScreen's own Scaffold — each builds its
/// own inner Scaffold, so the drawer has to be attached to each individually
/// rather than to AppShell's outer one for the hamburger icon to find it.
class HubDrawer extends ConsumerWidget {
  const HubDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final themeMode = ref.watch(themeModeProvider);

    void close() => Scaffold.of(context).closeDrawer();

    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Settings',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
            // Viewing someone else's profile pushes a route with no back
            // button — a Scaffold shows its drawer's hamburger icon instead
            // of a back arrow whenever both could apply, and every screen
            // now has this drawer. `go` (not `push`) replaces the current
            // location outright, so this always lands on the feed tab even
            // from several profiles deep.
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () {
                close();
                context.go('/feed');
              },
            ),
            const Divider(),
            if (me?.isAdmin ?? false)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Admin'),
                onTap: () {
                  close();
                  context.push('/admin');
                },
              ),
            if ((me?.isStudent ?? false) || (me?.isAlumni ?? false))
              ListTile(
                leading: const Icon(Icons.trending_up),
                title: const Text('Dashboard'),
                onTap: () {
                  close();
                  context.push('/dashboard');
                },
              ),
            if (me?.isBusiness ?? false)
              ListTile(
                leading: const Icon(Icons.trending_up),
                title: const Text('Dashboard'),
                onTap: () {
                  close();
                  context.push('/business-dashboard');
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit profile'),
              onTap: () {
                close();
                context.push('/edit-profile');
              },
            ),
            const Divider(),
            SwitchListTile(
              secondary: Icon(
                themeMode == ThemeMode.light
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              title: const Text('Light mode'),
              value: themeMode == ThemeMode.light,
              onChanged: (v) => ref
                  .read(themeModeProvider.notifier)
                  .set(v ? ThemeMode.light : ThemeMode.dark),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change password'),
              onTap: () {
                close();
                showChangePasswordDialog(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Delete account'),
              onTap: () {
                close();
                showDeleteAccountFlow(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () async {
                close();
                await ref.read(authRepoProvider).signOut();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
