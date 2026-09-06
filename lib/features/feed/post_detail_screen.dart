import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/post.dart';
import '../../providers.dart';
import '../../widgets/code_block.dart';
import '../../widgets/common.dart';

/// A post with its answers.
///
/// For an open bounty the author sees an "Accept" action on every other
/// person's comment; that calls the `accept_bounty_solution` RPC, which is the
/// only path that can write to the Logic Points ledger.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ref.read(postRepoProvider).addComment(widget.postId, content: text);
      _reply.clear();
      ref.invalidate(commentsProvider(widget.postId));
      ref.invalidate(postProvider(widget.postId));
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _accept(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Accept this answer?'),
        content: const Text(
          'The Logic Points move to whoever wrote it, and the bounty closes. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(postRepoProvider).acceptSolution(commentId);
      ref.invalidate(postProvider(widget.postId));
      ref.invalidate(commentsProvider(widget.postId));
      ref.invalidate(bountiesProvider);
      if (mounted) showMessage(context, 'Bounty awarded.');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    final comments = ref.watch(commentsProvider(widget.postId));
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: post.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(
          error: err,
          onRetry: () => ref.invalidate(postProvider(widget.postId)),
        ),
        data: (p) {
          final canAccept = p.isOpenBounty && me?.id == p.authorId;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                  children: [
                    _PostBody(post: p),
                    SectionHeader(
                      title: p.isBounty
                          ? 'Answers (${p.commentCount})'
                          : 'Comments (${p.commentCount})',
                    ),
                    comments.when(
                      loading: () => const Loading(),
                      error: (err, _) => ErrorView(error: err),
                      data: (list) {
                        if (list.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: EmptyState(
                              icon: Icons.mode_comment_outlined,
                              title: p.isBounty
                                  ? 'No answers yet'
                                  : 'No comments yet',
                              message: p.isOpenBounty
                                  ? 'Solve it first and take the '
                                      '${p.bountyPoints} LP.'
                                  : null,
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final c in list)
                              _CommentTile(
                                comment: c,
                                onAccept: canAccept && c.authorId != p.authorId
                                    ? () => _accept(c.id)
                                    : null,
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              _ReplyBar(
                controller: _reply,
                sending: _sending,
                hint: p.isBounty ? 'Write an answer…' : 'Add a comment…',
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PostBody extends StatelessWidget {
  const _PostBody({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.push('/user/${post.authorId}'),
                  child: Avatar(profile: author, radius: 22),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author?.displayName ?? 'Unknown',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      Text(
                        '${author?.subtitle ?? ''} · ${formatTimeAgo(post.createdAt)}',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ],
                  ),
                ),
                if (post.isBounty) PointsChip(points: post.bountyPoints),
              ],
            ),
            if (post.isBounty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  TagChip(
                    label: post.bountySolved ? 'SOLVED' : 'OPEN BOUNTY',
                    color: post.bountySolved
                        ? AppColors.accent
                        : AppColors.points,
                    icon: post.bountySolved
                        ? Icons.check_circle
                        : Icons.bolt,
                  ),
                  if (post.bountyModule != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: TagChip(
                        label: post.bountyModule!,
                        color: roleColor('STUDENT'),
                        icon: Icons.school_outlined,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),
            SelectableText(
              post.content,
              style: const TextStyle(height: 1.5, fontSize: 15),
            ),
            if (post.hasCode) ...[
              const SizedBox(height: 14),
              CodeBlock(code: post.codeSnippet!, language: post.codeLanguage),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.onAccept});

  final Comment comment;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: comment.isSolution
              ? AppColors.accent.withValues(alpha: 0.6)
              : Theme.of(context).colorScheme.outline,
          width: comment.isSolution ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/user/${comment.authorId}'),
                child: Avatar(profile: comment.author, radius: 15),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  comment.author?.displayName ?? 'Unknown',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (comment.isSolution)
                const TagChip(
                  label: 'ACCEPTED',
                  color: AppColors.accent,
                  icon: Icons.verified,
                ),
              const SizedBox(width: 6),
              Text(
                formatTimeAgo(comment.createdAt),
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(comment.content, style: const TextStyle(height: 1.45)),
          if (onAccept != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  foregroundColor: AppColors.button,
                  side: BorderSide(
                      color: AppColors.button.withValues(alpha: 0.5)),
                ),
                onPressed: onAccept,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Accept answer'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.controller,
    required this.sending,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
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
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const DottedProgressIndicator(size: 16, color: Colors.white)
                  : const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
