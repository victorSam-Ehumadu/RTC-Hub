import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(upcomingEventsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(upcomingEventsProvider),
        child: events.when(
          loading: () => const Loading(),
          error: (err, _) => ErrorView(
            error: err,
            onRetry: () => ref.invalidate(upcomingEventsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: const EmptyState(
                      icon: Icons.event_outlined,
                      title: 'No upcoming events',
                      message:
                          'Richfield administrators post campus and career '
                          'events here.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final event = list[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _month(event.eventDate.month),
                                style: monoStyle(
                                  size: 10,
                                  color: AppColors.accent,
                                ),
                              ),
                              Text(
                                '${event.eventDate.day}',
                                style: monoStyle(
                                  size: 19,
                                  weight: FontWeight.w800,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 5),
                              if (event.description != null)
                                Text(
                                  event.description!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.4),
                                ),
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  TagChip(
                                    label: _time(event.eventDate),
                                    color: AppColors.darkMuted,
                                    icon: Icons.schedule,
                                  ),
                                  if (event.isVirtual)
                                    const TagChip(
                                      label: 'Online',
                                      color: AppColors.accent,
                                      icon: Icons.videocam_outlined,
                                    )
                                  else if (event.location != null)
                                    TagChip(
                                      label: event.location!,
                                      color: AppColors.darkMuted,
                                      icon: Icons.place_outlined,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _month(int m) => const [
        'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
      ][m - 1];

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
