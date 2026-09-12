import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/recommendation.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// One search box over people, posts and opportunities.
///
/// A single call rather than three tabs: the user is looking for a *thing*,
/// and making them guess which category it lives in before searching is the
/// app's problem leaking into the interface. Results are grouped after the
/// fact, which gives the same scannability without the guess.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Opening a search screen and having to tap the box is a wasted step.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = ref.watch(searchTermProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'People, posts, opportunities…',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: term.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchTermProvider.notifier).state = '';
                    },
                  ),
          ),
          onChanged: (v) => ref.read(searchTermProvider.notifier).state = v,
        ),
      ),
      body: switch (term.trim().length) {
        0 => const _SearchIdle(),
        1 => const _TypeMore(),
        _ => results.when(
            loading: () => const TileListSkeleton(),
            error: (err, _) => ErrorView(error: err),
            data: (hits) => hits.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing found',
                    message: 'Try a different word, or fewer of them.',
                  )
                : _Results(hits: hits),
          ),
      },
    );
  }
}

class _TypeMore extends StatelessWidget {
  const _TypeMore();

  @override
  Widget build(BuildContext context) => const EmptyState(
        icon: Icons.keyboard,
        title: 'Keep typing',
        message: 'Two letters or more.',
      );
}

/// Before a term is typed, show who is worth connecting to. An empty search
/// screen is a dead end; suggestions make it a starting point.
class _SearchIdle extends ConsumerWidget {
  const _SearchIdle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(suggestedConnectionsProvider);

    return suggestions.when(
      loading: () => const TileListSkeleton(count: 4),
      error: (_, _) => const EmptyState(
        icon: Icons.search,
        title: 'Search RTC Hub',
        message: 'Find classmates, answers and opportunities.',
      ),
      data: (people) {
        if (people.isEmpty) {
          return const EmptyState(
            icon: Icons.search,
            title: 'Search RTC Hub',
            message: 'Find classmates, answers and opportunities.',
          );
        }
        return ListView(
          children: [
            const SectionHeader(title: 'People you may know'),
            for (final s in people) _SuggestionTile(suggestion: s),
          ],
        );
      },
    );
  }
}

class _SuggestionTile extends ConsumerWidget {
  const _SuggestionTile({required this.suggestion});

  final ConnectionSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = suggestion.profile;

    return ListTile(
      leading: Avatar(profile: profile, radius: 20),
      title: Text(
        profile.displayName,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        // The reason matters: a suggestion you cannot explain reads as a
        // random name.
        '${suggestion.reason} · ${profile.subtitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: _ConnectButton(userId: profile.id),
      onTap: () => context.push('/user/${profile.id}'),
    );
  }
}

class _ConnectButton extends ConsumerStatefulWidget {
  const _ConnectButton({required this.userId});

  final String userId;

  @override
  ConsumerState<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends ConsumerState<_ConnectButton> {
  bool _sent = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('Requested', style: TextStyle(fontSize: 12)),
      );
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await ref.read(connectionRepoProvider).request(widget.userId);
                if (mounted) setState(() => _sent = true);
              } catch (error) {
                if (context.mounted) showError(context, error);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: const Text('Connect'),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.hits});

  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context) {
    final people = hits.where((h) => h.isProfile).toList();
    final posts = hits.where((h) => h.isPost).toList();
    final jobs = hits.where((h) => h.isOpportunity).toList();

    return ListView(
      children: [
        if (people.isNotEmpty) ...[
          const SectionHeader(title: 'People'),
          for (final h in people) _HitTile(hit: h),
        ],
        if (posts.isNotEmpty) ...[
          const SectionHeader(title: 'Posts'),
          for (final h in posts) _HitTile(hit: h),
        ],
        if (jobs.isNotEmpty) ...[
          const SectionHeader(title: 'Opportunities'),
          for (final h in jobs) _HitTile(hit: h),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    final (icon, colour) = switch (hit.kind) {
      'profile' => (Icons.person_outline, roleColor(hit.extra['role'] as String?)),
      'post' => (
          hit.extra['is_bounty'] == true ? Icons.bolt : Icons.article_outlined,
          hit.extra['is_bounty'] == true ? AppColors.points : roleColor('STUDENT'),
        ),
      _ => (Icons.work_outline, AppColors.accent),
    };

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: colour.withValues(alpha: 0.14),
        child: Icon(icon, size: 18, color: colour),
      ),
      title: Text(
        hit.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: hit.subtitle == null
          ? null
          : Text(
              hit.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: muted),
            ),
      trailing: hit.isPost && hit.extra['faculty'] != null
          ? FacultyChip(faculty: hit.extra['faculty'] as String?, compact: true)
          : null,
      onTap: () => context.push(hit.route),
    );
  }
}
