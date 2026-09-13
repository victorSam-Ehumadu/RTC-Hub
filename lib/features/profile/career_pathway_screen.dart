import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/portfolio.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// The career pathway explorer — §2.5.
///
/// *"A career pathway explorer allows students to view the career
/// trajectories of alumni who studied the same programme, showing where
/// graduates have ended up and what roles they have held."*
///
/// The screen opens on the student's own programme, because that is the
/// question they came to ask; the picker exists for the student who is
/// wondering whether a different course leads somewhere better.
///
/// Each alumnus is drawn as a vertical timeline rather than a list of jobs.
/// A trajectory is the point — "graduated, then support desk, then junior
/// dev, then this" says something a bag of job titles does not.
class CareerPathwayScreen extends ConsumerWidget {
  const CareerPathwayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(pathwayCourseProvider);
    final me = ref.watch(meProvider);
    final pathway = ref.watch(careerPathwayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Where graduates go'),
        actions: [
          IconButton(
            tooltip: 'Choose a programme',
            icon: const Icon(Icons.filter_list),
            onPressed: () => _pickCourse(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Icon(Icons.school_outlined,
                    size: 15, color: facultyColor(me?.faculty)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected ?? me?.course ?? 'Your programme',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                if (selected != null)
                  TextButton(
                    onPressed: () =>
                        ref.read(pathwayCourseProvider.notifier).state = null,
                    child: const Text('Mine'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(careerPathwayProvider),
              child: pathway.when(
                loading: () => const TileListSkeleton(count: 4),
                error: (err, _) => ErrorView(
                  error: err,
                  onRetry: () => ref.invalidate(careerPathwayProvider),
                ),
                data: (people) {
                  if (people.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.6,
                          child: EmptyState(
                            icon: Icons.timeline_outlined,
                            title: 'No alumni yet',
                            message:
                                'Once graduates from this programme join and '
                                'fill in their experience, their paths show '
                                'up here.',
                            action: OutlinedButton(
                              onPressed: () => _pickCourse(context, ref),
                              child: const Text('Try another programme'),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                    itemCount: people.length,
                    itemBuilder: (_, i) => _PathwayCard(entry: people[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCourse(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => const _CoursePicker(),
    );
    if (chosen == null) return;
    ref.read(pathwayCourseProvider.notifier).state =
        chosen.isEmpty ? null : chosen;
  }
}

class _CoursePicker extends ConsumerWidget {
  const _CoursePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(pathwayCoursesProvider);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        children: [
          const SizedBox(height: 14),
          const SectionHeader(title: 'Programmes with alumni'),
          Expanded(
            child: courses.when(
              loading: () => const TileListSkeleton(count: 5, hasAvatar: false),
              error: (err, _) => ErrorView(error: err),
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.school_outlined,
                      title: 'No alumni have joined yet',
                    )
                  : ListView(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text('My programme'),
                          onTap: () => Navigator.pop(context, ''),
                        ),
                        const Divider(height: 1),
                        for (final c in list)
                          ListTile(
                            title: Text(
                              c.course,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                            trailing: Text(
                              '${c.alumni}',
                              style: monoStyle(size: 12),
                            ),
                            onTap: () => Navigator.pop(context, c.course),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PathwayCard extends StatelessWidget {
  const _PathwayCard({required this.entry});

  final CareerPathwayEntry entry;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/user/${entry.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: roleColor('ALUMNI').withValues(alpha: 0.15),
                    backgroundImage: entry.avatarUrl == null
                        ? null
                        : NetworkImage(entry.avatarUrl!),
                    child: entry.avatarUrl != null
                        ? null
                        : Text(
                            entry.fullName.isEmpty
                                ? '?'
                                : entry.fullName[0].toUpperCase(),
                            style: TextStyle(
                              color: roleColor('ALUMNI'),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (entry.headline != null) entry.headline!
                            else if (entry.fieldOfWork != null)
                              entry.fieldOfWork!,
                            if (entry.graduationYear != null)
                              'class of ${entry.graduationYear}',
                          ].join(' · '),
                          style: TextStyle(fontSize: 11.5, color: muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (entry.roles.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Has not added their work history yet.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ] else ...[
                const SizedBox(height: 14),
                for (var i = 0; i < entry.roles.length; i++)
                  _TimelineRow(
                    role: entry.roles[i],
                    isFirst: i == 0,
                    isLast: i == entry.roles.length - 1,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One step in a trajectory, with the connecting line drawn between steps.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.role,
    required this.isFirst,
    required this.isLast,
  });

  final PathwayRole role;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    // The current role is the one a student is actually looking for.
    final accent = role.isCurrent ? AppColors.success : muted;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: role.isCurrent ? AppColors.success : Colors.transparent,
                    border: Border.all(color: accent, width: 1.6),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.4,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          role.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                isFirst ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (role.isVenture) ...[
                        const SizedBox(width: 6),
                        const TagChip(
                          label: 'FOUNDED',
                          color: AppColors.points,
                          icon: Icons.rocket_launch_outlined,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [role.company, role.period]
                        .where((p) => p.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(fontSize: 11.5, color: muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
