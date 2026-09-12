import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../shell/app_shell.dart';
import 'post_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(feedModeProvider);
    final feed = ref.watch(feedProvider);

    return Scaffold(
      appBar: HubAppBar(
        title: 'RTC Hub',
        actions: [
          IconButton(
            onPressed: () => context.push('/events'),
            icon: const Icon(Icons.event_outlined),
            tooltip: 'Events',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/compose'),
        child: const Icon(Icons.edit),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SegmentedButton<FeedMode>(
              segments: const [
                ButtonSegment(
                  value: FeedMode.following,
                  label: Text('Following'),
                  icon: Icon(Icons.people_outline, size: 16),
                ),
                ButtonSegment(
                  value: FeedMode.discover,
                  label: Text('Discover'),
                  icon: Icon(Icons.explore_outlined, size: 16),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  ref.read(feedModeProvider.notifier).state = s.first,
            ),
          ),
          const _FacultyScopeBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(feedProvider),
              child: feed.when(
                loading: () => const PostListSkeleton(),
                error: (err, _) => ErrorView(
                  error: err,
                  onRetry: () => ref.invalidate(feedProvider),
                ),
                data: (posts) {
                  if (posts.isEmpty) {
                    return ListView(
                      // Needs to scroll for pull-to-refresh to work when empty.
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.6,
                          child: mode == FeedMode.following
                              ? EmptyState(
                                  icon: Icons.group_add_outlined,
                                  title: 'Your feed is quiet',
                                  message:
                                      'Following shows posts from people you '
                                      'are connected to. Switch to Discover to '
                                      'find classmates and alumni.',
                                  action: FilledButton(
                                    onPressed: () =>
                                        ref
                                                .read(feedModeProvider.notifier)
                                                .state =
                                            FeedMode.discover,
                                    child: const Text('Browse Discover'),
                                  ),
                                )
                              : EmptyState(
                                  icon: Icons.forum_outlined,
                                  title: 'Nothing posted yet',
                                  message:
                                      'Be the first to share something you built.',
                                  action: FilledButton(
                                    onPressed: () => context.push('/compose'),
                                    child: const Text('Write a post'),
                                  ),
                                ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: posts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => PostCard(post: posts[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet line saying whose content this feed contains.
///
/// Migration 0007 scopes the feed by faculty inside RLS, which is the right
/// place for it — but an invisible rule reads as an arbitrary one. Naming it
/// costs a single line and turns "why is this empty" into something the
/// reader can act on.
class _FacultyScopeBar extends ConsumerWidget {
  const _FacultyScopeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final interests = me?.contentInterests ?? const <String>[];
    if (interests.isEmpty) return const SizedBox.shrink();

    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          for (final faculty in interests) ...[
            FacultyChip(faculty: faculty, compact: true),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              interests.length > 1
                  ? 'Showing both faculties'
                  : 'Scoped to your faculty',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
