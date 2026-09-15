import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';
import '../shell/settings_drawer.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final requests = ref.watch(connectionRequestsProvider);

    return Scaffold(
      drawer: const HubDrawer(),
      appBar: const HubAppBar(title: 'Messages'),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startChat(context, ref),
        child: const Icon(Icons.edit_square),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(conversationsProvider)
            ..invalidate(connectionRequestsProvider);
        },
        child: conversations.when(
          loading: () => const Loading(),
          error: (err, _) => ErrorView(
            error: err,
            onRetry: () => ref.invalidate(conversationsProvider),
          ),
          data: (list) {
            final pending = requests.valueOrNull ?? const [];

            if (list.isEmpty && pending.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'No conversations yet',
                      message: 'Find someone on the Discover feed and say hello.',
                      action: FilledButton(
                        onPressed: () => _startChat(context, ref),
                        child: const Text('Find people'),
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                if (pending.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHeader(title: 'Connection requests'),
                  ),
                  for (final c in pending)
                    _RequestTile(
                      connection: c,
                      onDone: () {
                        ref
                          ..invalidate(connectionRequestsProvider)
                          ..invalidate(connectionsProvider);
                      },
                    ),
                  const Divider(height: 24),
                ],
                for (final convo in list)
                  ListTile(
                    onTap: () => context.push('/chat/${convo.other.id}'),
                    leading: Avatar(profile: convo.other),
                    title: Text(
                      convo.other.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      convo.lastMessage.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatTimeAgo(convo.lastMessage.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        if (convo.unread > 0) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${convo.unread}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF04120A),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _startChat(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PeoplePicker(),
    );
    if (picked != null && context.mounted) {
      context.push('/chat/${picked.id}');
    }
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.connection, required this.onDone});

  final Connection connection;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sender = connection.sender;

    Future<void> respond(bool accept) async {
      try {
        await ref
            .read(connectionRepoProvider)
            .respond(connection.id, accept: accept);
        onDone();
        if (context.mounted) {
          showMessage(context, accept ? 'Connected.' : 'Request declined.');
        }
      } catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return ListTile(
      leading: Avatar(profile: sender),
      title: Text(
        sender?.displayName ?? 'Someone',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(sender?.subtitle ?? 'wants to connect'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => respond(false),
            icon: const Icon(Icons.close),
            color: AppColors.danger,
          ),
          IconButton(
            onPressed: () => respond(true),
            icon: const Icon(Icons.check),
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

/// Search sheet for starting a new conversation.
class _PeoplePicker extends ConsumerStatefulWidget {
  const _PeoplePicker();

  @override
  ConsumerState<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends ConsumerState<_PeoplePicker> {
  String _term = '';

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(peopleSearchProvider(_term));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search students, alumni, companies…',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (v) => setState(() => _term = v),
              ),
            ),
            Expanded(
              child: results.when(
                loading: () => const Loading(),
                error: (err, _) => ErrorView(error: err),
                data: (people) => people.isEmpty
                    ? const EmptyState(
                        icon: Icons.person_search_outlined,
                        title: 'Nobody found',
                      )
                    : ListView.builder(
                        itemCount: people.length,
                        itemBuilder: (_, i) => ListTile(
                          onTap: () => Navigator.pop(context, people[i]),
                          leading: Avatar(profile: people[i], radius: 20),
                          title: Text(people[i].displayName),
                          subtitle: Text(people[i].subtitle),
                          trailing: RoleBadge(role: people[i].role),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
