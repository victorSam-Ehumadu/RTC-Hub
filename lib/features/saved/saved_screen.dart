import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../feed/post_card.dart';

/// Bookmarked posts and opportunities.
///
/// Saved items are private — nobody sees what someone else bookmarked, and
/// no feature wants it, so the policy in migration 0011 is a flat
/// `user_id = auth.uid()` with no read-sharing at all.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(savedPostsProvider);
    final jobs = ref.watch(savedOpportunitiesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Posts'), Tab(text: 'Opportunities')],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: () async => ref.invalidate(savedPostsProvider),
              child: posts.when(
                loading: () => const PostListSkeleton(count: 3),
                error: (err, _) => ErrorView(
                  error: err,
                  onRetry: () => ref.invalidate(savedPostsProvider),
                ),
                data: (list) => list.isEmpty
                    ? _empty(
                        context,
                        Icons.bookmark_border,
                        'Nothing saved yet',
                        'Tap the bookmark on a post to keep it here.',
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => PostCard(
                          post: list[i],
                          onChanged: () =>
                              ref.invalidate(savedPostsProvider),
                        ),
                      ),
              ),
            ),
            RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(savedOpportunitiesProvider),
              child: jobs.when(
                loading: () => const OpportunityListSkeleton(),
                error: (err, _) => ErrorView(
                  error: err,
                  onRetry: () => ref.invalidate(savedOpportunitiesProvider),
                ),
                data: (list) => list.isEmpty
                    ? _empty(
                        context,
                        Icons.work_outline,
                        'No saved opportunities',
                        'Bookmark a listing to come back to it.',
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final o = list[i];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              title: Text(
                                o.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  o.business?.displayName ?? '',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.bookmark,
                                    color: AppColors.points),
                                onPressed: () async {
                                  await ref
                                      .read(engagementRepoProvider)
                                      .unsaveOpportunity(o.id);
                                  ref
                                    ..invalidate(savedOpportunitiesProvider)
                                    ..invalidate(savedIdsProvider);
                                },
                              ),
                              onTap: () => context.go('/opportunities'),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty states have to scroll, or pull-to-refresh does nothing on the one
  /// screen where a user is most likely to try it.
  Widget _empty(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) =>
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: EmptyState(icon: icon, title: title, message: message),
          ),
        ],
      );
}
