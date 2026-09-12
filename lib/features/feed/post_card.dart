import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/post.dart';
import '../../providers.dart';
import '../../widgets/code_block.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import 'edit_post_sheet.dart';
import '../../widgets/sheet_preview.dart';

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
        reactionCount:
            _post.reactionCount +
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
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);

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
                  // Faculty is what 0007 scopes the feed by, so showing it
                  // makes the rule legible instead of mysterious.
                  FacultyChip(faculty: _post.faculty, compact: true),
                  if (ref.watch(meProvider)?.id == _post.authorId)
                    _AuthorMenu(
                      post: _post,
                      onDeleted: widget.onChanged,
                      onEdited: (updated) => setState(() => _post = updated),
                    ),
                  if (_post.isBounty) ...[
                    const SizedBox(width: 6),
                    PointsChip(points: _post.bountyPoints),
                  ],
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
              Text(
                _post.content,
                style: const TextStyle(height: 1.45, fontSize: 14.5),
              ),

              if (_post.hasCode) ...[
                const SizedBox(height: 12),
                CodeBlock(
                  code: _post.codeSnippet!,
                  language: _post.codeLanguage,
                  maxLines: 12,
                  runnable: false,
                ),
              ],

              if (_post.hasSheet) ...[
                const SizedBox(height: 12),
                SheetPreview(sheet: _post.sheet!, title: 'sheet', maxRows: 4),
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
                  _ReactionButton(post: _post, onReact: _react),
                  const SizedBox(width: 16),
                  Icon(Icons.mode_comment_outlined, size: 17, color: muted),
                  const SizedBox(width: 5),
                  Text(
                    '${_post.commentCount}',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                  const Spacer(),
                  _SaveButton(postId: _post.id),
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
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);

    return Semantics(
      button: true,
      label: reacted
          ? 'Reacted ${post.myReaction}. ${post.reactionCount} reactions. '
                'Tap to remove, long press to change.'
          : '${post.reactionCount} reactions. Tap to react, long press to '
                'choose an emoji.',
      child: InkWell(
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
        child: Container(
          // 40x40 minimum: the old 4px padding gave a target barely larger
          // than the glyph, which is a miss on a phone held one-handed.
          constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
      ),
    );
  }
}

/// Bookmark toggle.
///
/// Reads the saved-id set rather than asking per card: the alternative is a
/// round-trip for every row, which on a twenty-post feed is twenty requests
/// to draw an icon. Optimistic like the reaction button, and for the same
/// reason — a bookmark that waits on the network feels broken.
class _SaveButton extends ConsumerStatefulWidget {
  const _SaveButton({required this.postId});

  final String postId;

  @override
  ConsumerState<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends ConsumerState<_SaveButton> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedIdsProvider).valueOrNull ?? const <String>{};
    final isSaved = _override ?? saved.contains(widget.postId);
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);

    return IconButton(
      tooltip: isSaved ? 'Remove from saved' : 'Save',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: Icon(
        isSaved ? Icons.bookmark : Icons.bookmark_border,
        color: isSaved ? AppColors.points : muted,
      ),
      onPressed: () async {
        setState(() => _override = !isSaved);
        try {
          final repo = ref.read(engagementRepoProvider);
          if (isSaved) {
            await repo.unsavePost(widget.postId);
          } else {
            await repo.savePost(widget.postId);
          }
          ref.invalidate(savedIdsProvider);
        } catch (error) {
          if (!context.mounted) return;
          setState(() => _override = isSaved);
          showError(context, error);
        }
      },
    );
  }
}

/// Edit and delete, for the person who wrote it.
///
/// Behind an overflow menu rather than inline buttons: these are the two
/// destructive-ish actions on the card and they should not compete with
/// reacting and commenting, which is what the card is for.
class _AuthorMenu extends ConsumerWidget {
  const _AuthorMenu({
    required this.post,
    required this.onDeleted,
    required this.onEdited,
  });

  final Post post;
  final VoidCallback? onDeleted;
  final ValueChanged<Post> onEdited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Post options',
      icon: Icon(
        Icons.more_horiz,
        size: 18,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('Edit'),
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.danger,
            ),
            title: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ),
      ],
      onSelected: (choice) async {
        if (choice == 'edit') {
          final updated = await showEditPostSheet(context, post);
          if (updated != null) onEdited(updated);
          return;
        }

        final gone = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete this post?'),
            content: Text(
              post.isBounty && post.bountySolved
                  ? 'The Logic Points already awarded stay with whoever '
                        'earned them, but the post and its answers go.'
                  : 'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (gone != true) return;

        try {
          await ref.read(postRepoProvider).delete(post.id);
          onDeleted?.call();
          if (context.mounted) showMessage(context, 'Post deleted.');
        } catch (error) {
          if (context.mounted) showError(context, error);
        }
      },
    );
  }
}
