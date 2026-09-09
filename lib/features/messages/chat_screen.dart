import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// A one-to-one thread.
///
/// The message list is a Riverpod stream fed by Supabase Realtime, which is
/// what replaced the Socket.IO room the web client used to join.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.otherId});

  final String otherId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Clear the unread badge for this thread as soon as it is opened.
    Future.microtask(() async {
      try {
        await ref.read(messageRepoProvider).markThreadRead(widget.otherId);
        ref.invalidate(conversationsProvider);
      } catch (_) {
        // Not worth interrupting the conversation over.
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ref.read(messageRepoProvider).send(widget.otherId, text);
      _input.clear();
      ref.invalidate(conversationsProvider);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = ref.watch(profileProvider(widget.otherId));
    final thread = ref.watch(threadProvider(widget.otherId));
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(
        title: other.when(
          loading: () => const Text('…'),
          error: (_, _) => const Text('Chat'),
          data: (p) => InkWell(
            onTap: () => context.push('/user/${p.id}'),
            child: Row(
              children: [
                Avatar(profile: p, radius: 16),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.displayName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        p.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: thread.when(
              loading: () => const Loading(),
              error: (err, _) => ErrorView(
                error: err,
                onRetry: () => ref.invalidate(threadProvider(widget.otherId)),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return const EmptyState(
                    icon: Icons.waving_hand_outlined,
                    title: 'Say hello',
                    message: 'No messages in this conversation yet.',
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true, // newest at the bottom, grows upward
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final message = messages[messages.length - 1 - i];
                    return _Bubble(
                      message: message,
                      mine: me != null && message.isMine(me.id),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.button,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const DottedProgressIndicator(
                            size: 16,
                            color: Colors.white,
                          )
                        : const Icon(Icons.send, size: 18),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? AppColors.accent.withValues(alpha: 0.16)
              : scheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border: Border.all(
            color: mine
                ? AppColors.accent.withValues(alpha: 0.35)
                : scheme.outline,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(message.content, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 3),
            Text(
              formatTimeAgo(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
