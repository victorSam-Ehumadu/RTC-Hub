import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import 'recommendations_section.dart';
import '../../widgets/skeleton.dart';
import '../feed/post_card.dart';
import '../shell/app_shell.dart';

/// Someone's profile — theirs or your own.
///
/// [userId] null means "me", which is what the Profile tab routes to.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.userId});

  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _viewRecorded = false;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final isSelf = widget.userId == null || widget.userId == me?.id;
    final targetId = widget.userId ?? me?.id;

    if (targetId == null) return const Scaffold(body: Loading());

    // Count the visit once per screen, and never your own.
    if (!isSelf && !_viewRecorded) {
      _viewRecorded = true;
      ref.read(profileRepoProvider).recordView(targetId);
    }

    final profile =
        isSelf && me != null ? AsyncValue.data(me) : ref.watch(profileProvider(targetId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const HubBanner(),
        iconTheme: const IconThemeData(color: hubBannerForeground),
        actionsIconTheme: const IconThemeData(color: hubBannerForeground),
        title: Text(
          isSelf ? 'Your profile' : 'Profile',
          style: const TextStyle(
            color: hubBannerForeground,
            fontWeight: FontWeight.w800,
            shadows: hubBannerTitleShadow,
          ),
        ),
        actions: [
          if (isSelf) ...[
            if (me?.isAdmin ?? false)
              IconButton(
                tooltip: 'Admin',
                onPressed: () => context.push('/admin'),
                icon: const Icon(Icons.admin_panel_settings_outlined),
              ),
            if ((me?.isStudent ?? false) || (me?.isAlumni ?? false))
              IconButton(
                tooltip: 'Dashboard',
                onPressed: () => context.push('/dashboard'),
                icon: const Icon(Icons.trending_up),
              ),
            IconButton(
              tooltip: 'Edit',
              onPressed: () => context.push('/edit-profile'),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
      body: profile.when(
        loading: () => const ProfileSkeleton(),
        error: (err, _) => ErrorView(
          error: err,
          onRetry: () => ref.invalidate(profileProvider(targetId)),
        ),
        data: (p) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(myProfileProvider)
              ..invalidate(profileProvider(targetId))
              ..invalidate(skillsProvider(targetId))
              ..invalidate(postsByAuthorProvider(targetId));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              _Header(profile: p, isSelf: isSelf),
              if (isSelf) _CompletenessBar(profile: p),
              if (!isSelf) _ConnectRow(profile: p),
              if (p.bio != null && p.bio!.isNotEmpty) ...[
                const SectionHeader(title: 'About'),
                Text(p.bio!, style: const TextStyle(height: 1.5)),
              ],
              _SkillsSection(userId: p.id, isSelf: isSelf),
              _ExperienceSection(userId: p.id, isSelf: isSelf),
              RecommendationsSection(
                userId: p.id,
                isSelf: isSelf,
                subjectName: p.fullName.split(' ').first,
              ),
              if (isSelf) _StatsSection(userId: p.id),
              _PostsSection(userId: p.id),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.profile, required this.isSelf});

  final Profile profile;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(logicPointsProvider(profile.id));

    return Column(
      children: [
        Row(
          children: [
            Avatar(profile: profile, radius: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      RoleBadge(role: profile.role),
                      if (profile.studentNumber != null)
                        TagChip(
                          label: profile.studentNumber!,
                          color: AppColors.darkMuted,
                          icon: Icons.badge_outlined,
                        ),
                      PointsChip(points: points.valueOrNull ?? 0),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Nudges the user to finish their profile. The score is computed by
/// `profiles_before_update()`, so it is always in step with the data.
class _CompletenessBar extends StatelessWidget {
  const _CompletenessBar({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    if (profile.profileCompleteness >= 100) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Profile ${profile.profileCompleteness}% complete',
                style: monoStyle(size: 11.5),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.push('/edit-profile'),
                child: const Text('Improve'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: profile.profileCompleteness / 100,
              minHeight: 6,
              color: AppColors.accent,
              backgroundColor:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectRow extends ConsumerWidget {
  const _ConnectRow({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionWithProvider(profile.id));

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          Expanded(
            child: connection.when(
              loading: () => const OutlinedButton(
                onPressed: null,
                child: Text('…'),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (c) {
                if (c == null) {
                  return FilledButton.icon(
                    onPressed: () async {
                      try {
                        await ref
                            .read(connectionRepoProvider)
                            .request(profile.id);
                        ref.invalidate(connectionWithProvider(profile.id));
                        if (context.mounted) {
                          showMessage(context, 'Request sent.');
                        }
                      } catch (error) {
                        if (context.mounted) showError(context, error);
                      }
                    },
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Connect'),
                  );
                }
                if (c.isAccepted) {
                  return const OutlinedButton(
                    onPressed: null,
                    child: Text('Connected'),
                  );
                }
                return const OutlinedButton(
                  onPressed: null,
                  child: Text('Request pending'),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/chat/${profile.id}'),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('Message'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillsSection extends ConsumerWidget {
  const _SkillsSection({required this.userId, required this.isSelf});

  final String userId;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillsProvider(userId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Skills',
          action: isSelf
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addSkill(context, ref),
                  icon: const Icon(Icons.add, size: 20),
                )
              : null,
        ),
        skills.when(
          loading: () => const SizedBox(height: 40, child: Loading()),
          error: (err, _) => ErrorView(error: err),
          data: (list) => list.isEmpty
              ? Text(
                  isSelf
                      ? 'Add the skills you want recruiters to find you by.'
                      : 'No skills listed yet.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in list)
                      InputChip(
                        avatar: s.verified
                            ? const Icon(Icons.verified,
                                size: 15, color: AppColors.accent)
                            : null,
                        label: Text(
                          s.endorsements > 0
                              ? '${s.name} · ${s.endorsements}'
                              : s.name,
                        ),
                        onPressed: isSelf
                            ? null
                            : () async {
                                try {
                                  await ref
                                      .read(profileRepoProvider)
                                      .endorse(s.id);
                                  ref.invalidate(skillsProvider(userId));
                                  if (context.mounted) {
                                    showMessage(context, 'Endorsed ${s.name}.');
                                  }
                                } catch (error) {
                                  if (context.mounted) showError(context, error);
                                }
                              },
                        onDeleted: isSelf
                            ? () async {
                                await ref
                                    .read(profileRepoProvider)
                                    .removeSkill(s.id);
                                ref.invalidate(skillsProvider(userId));
                                ref.invalidate(myProfileProvider);
                              }
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _addSkill(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();

    // Popping the dialog synchronously from a callback on the autofocused
    // TextField (Enter key, or a button tapped while it still has focus)
    // races the field's own focus/keyboard teardown and can trip Flutter's
    // '_dependents.isEmpty' assertion. Deferring to the next frame lets that
    // teardown finish before the dialog route is torn down.
    void close(BuildContext dialogContext, [String? value]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialogContext.mounted) Navigator.pop(dialogContext, value);
      });
    }

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a skill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. PostgreSQL'),
          onSubmitted: (v) => close(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => close(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => close(dialogContext, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(profileRepoProvider).addSkill(name);
      ref.invalidate(skillsProvider(userId));
      ref.invalidate(myProfileProvider);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _ExperienceSection extends ConsumerWidget {
  const _ExperienceSection({required this.userId, required this.isSelf});

  final String userId;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final experience = ref.watch(experienceProvider(userId));

    return experience.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty && !isSelf) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Experience'),
            if (list.isEmpty)
              Text(
                'No experience added yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            for (final w in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.work_outline),
                title: Text(
                  w.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(w.company),
                trailing: isSelf
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          await ref
                              .read(profileRepoProvider)
                              .removeExperience(w.id);
                          ref.invalidate(experienceProvider(userId));
                          ref.invalidate(myProfileProvider);
                        },
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(studentStatsProvider(userId));

    final me = ref.watch(meProvider);
    final showDashboardLink = (me?.isStudent ?? false) || (me?.isAlumni ?? false);

    return stats.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Your numbers',
            action: showDashboardLink
                ? TextButton(
                    onPressed: () => context.push('/dashboard'),
                    child: const Text('Full dashboard'),
                  )
                : null,
          ),
          Row(
            children: [
              _Stat(label: 'Views', value: '${s.profileViews}'),
              _Stat(label: 'Posts', value: '${s.posts}'),
              _Stat(label: 'Connections', value: '${s.connections}'),
              _Stat(label: 'LP', value: '${s.logicPoints}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          children: [
            Text(value, style: monoStyle(size: 18, weight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostsSection extends ConsumerWidget {
  const _PostsSection({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsByAuthorProvider(userId));

    return posts.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Proof of work (${list.length})'),
          if (list.isEmpty)
            Text(
              'Nothing posted yet.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          for (final p in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PostCard(post: p),
            ),
        ],
      ),
    );
  }
}
