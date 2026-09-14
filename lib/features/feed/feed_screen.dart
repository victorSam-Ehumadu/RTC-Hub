import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';
import '../shell/settings_drawer.dart';
import 'post_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(feedModeProvider);
    final feed = ref.watch(feedProvider);

    return Scaffold(
      drawer: const HubDrawer(),
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(feedProvider),
              child: feed.when(
                loading: () => const Loading(),
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
                                    onPressed: () => ref
                                        .read(feedModeProvider.notifier)
                                        .state = FeedMode.discover,
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
