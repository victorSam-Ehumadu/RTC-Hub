import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/post.dart';
import '../../providers.dart';
import '../../widgets/code_block.dart';
import '../../widgets/common.dart';

/// One post in a feed or bounty list.
///
/// Reactions are applied optimistically — the count moves immediately and
/// rolls back if the write is rejected — because a round-trip to Supabase on
/// every tap makes the feed feel dead.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post, this.onChanged});

  final Post post;
  final VoidCallback? onChanged;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  late Post _post = widget.post;

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (old.post != widget.post) _post = widget.post;
  }

  Future<void> _react(String emoji) async {
    final before = _post;
    final removing = _post.myReaction == emoji;

    setState(() {
      _post = _post.copyWith(
        reactionCount: _post.reactionCount +
            (removing ? -1 : (_post.myReaction == null ? 1 : 0)),
        myReaction: removing ? null : emoji,
        clearMyReaction: removing,
      );
    });

    try {
      await ref.read(postRepoProvider).toggleReaction(_post.id, emoji: emoji);
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _post = before);
      showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = _post.author;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/post/${_post.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.push('/user/${_post.authorId}'),
                    child: Avatar(profile: author, radius: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                author?.displayName ?? 'Unknown',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (author != null) RoleBadge(role: author.role),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${author?.subtitle ?? ''} · ${formatTimeAgo(_post.createdAt)}',
                          style: TextStyle(fontSize: 11.5, color: muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_post.isBounty)
                    PointsChip(points: _post.bountyPoints),
                ],
              ),

              if (_post.isBounty && _post.bountySolved)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: TagChip(
                    label: 'SOLVED',
                    color: AppColors.accent,
                    icon: Icons.check_circle,
                  ),
                ),

              const SizedBox(height: 12),
              Text(_post.content, style: const TextStyle(height: 1.45, fontSize: 14.5)),

              if (_post.hasCode) ...[
                const SizedBox(height: 12),
                CodeBlock(
                  code: _post.codeSnippet!,
                  language: _post.codeLanguage,
                  maxLines: 12,
                ),
              ],

              if (_post.bountyModule != null) ...[
                const SizedBox(height: 10),
                TagChip(
                  label: _post.bountyModule!,
                  color: roleColor('STUDENT'),
                  icon: Icons.school_outlined,
                ),
              ],

              const SizedBox(height: 12),
              Row(
                children: [
                  _ReactionButton(
                    post: _post,
                    onReact: _react,
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.mode_comment_outlined, size: 17, color: muted),
                  const SizedBox(width: 5),
                  Text('${_post.commentCount}',
                      style: TextStyle(fontSize: 13, color: muted)),
                  const Spacer(),
                  if (_post.isOpenBounty)
                    TextButton(
                      onPressed: () => context.push('/post/${_post.id}'),
                      child: const Text('Answer'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({required this.post, required this.onReact});

  final Post post;
  final Future<void> Function(String) onReact;

  @override
  Widget build(BuildContext context) {
    final reacted = post.myReaction != null;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onReact(post.myReaction ?? '👍'),
      onLongPress: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in kReactionEmojis)
                    IconButton(
                      iconSize: 30,
                      onPressed: () => Navigator.pop(context, emoji),
                      icon: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                ],
              ),
            ),
          ),
        );
        if (picked != null) await onReact(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reacted)
              Text(post.myReaction!, style: const TextStyle(fontSize: 15))
            else
              Icon(Icons.favorite_border, size: 17, color: muted),
            const SizedBox(width: 5),
            Text(
              '${post.reactionCount}',
              style: TextStyle(
                fontSize: 13,
                color: reacted ? AppColors.accent : muted,
                fontWeight: reacted ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
