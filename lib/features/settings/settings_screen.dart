import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Appearance and account settings.
///
/// Theme lives here rather than in the profile editor because it is a device
/// preference — nothing on this screen touches the database.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionHeader(title: 'Appearance'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_outlined, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_outlined, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto_outlined, size: 16),
              ),
            ],
            selected: {choice.mode},
            onSelectionChanged: (s) => controller.setMode(s.first),
          ),

          const SectionHeader(title: 'Theme'),
          for (final palette in kPalettes)
            _PaletteTile(
              palette: palette,
              selected: palette.id == choice.paletteId,
              dark: Theme.of(context).brightness == Brightness.dark,
              onTap: () => controller.setPalette(palette.id),
            ),

          if (me != null) ...[
            const SectionHeader(title: 'Account'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: const Text('Saved items'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/saved'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Edit profile'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/edit-profile'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.school_outlined,
                        color: facultyColor(me.faculty)),
                    title: const Text('Faculty'),
                    subtitle: Text(
                      me.isBusiness
                          ? 'Showing content from '
                              '${me.contentInterests.map(facultyLabel).join(' and ')}'
                          : facultyLabel(me.faculty),
                    ),
                    trailing: me.isBusiness
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: me.isBusiness
                        ? () => context.push('/edit-profile')
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                final out = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text(
                        'You will need your password to sign back in.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (out != true) return;
                await ref.read(authRepoProvider).signOut();
                if (context.mounted) context.go('/login');
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A palette row that previews itself, so the choice is visible without
/// having to apply it first.
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? palette.darkBg : palette.lightBg;
    final surface = dark ? palette.darkSurface : palette.lightSurface;
    final border = dark ? palette.darkBorder : palette.lightBorder;
    final text = dark ? palette.darkText : palette.lightText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? palette.accent
                  : Theme.of(context).colorScheme.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Miniature of the theme: background, a card, and the accent.
              Container(
                width: 54,
                height: 44,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: border),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 6,
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Container(
                            width: 10,
                            height: 6,
                            decoration: BoxDecoration(
                              color: palette.button,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: text.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      palette.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      palette.description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: palette.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
