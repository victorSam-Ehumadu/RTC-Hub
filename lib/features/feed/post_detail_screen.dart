import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../core/theme.dart';
import '../../models/post.dart';
import '../../providers.dart';
import '../../widgets/code_block.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sheet_preview.dart';
import 'submit_answer_sheet.dart';

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
  void initState() {
    super.initState();
    // Opening the thread is reading it, so the notifications that pointed
    // here should stop counting against the bell.
    Future.microtask(() async {
      try {
        await ref
            .read(notificationRepoProvider)
            .markPostNotificationsRead(widget.postId);
        ref
          ..invalidate(unreadCountProvider)
          ..invalidate(notificationsProvider);
      } catch (_) {
        // Cosmetic; never block the thread on it.
      }
    });
  }

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
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Both sections plus the post itself — a submission moves the answer
  /// count, and accepting one closes the bounty.
  void _refresh() {
    ref
      ..invalidate(postProvider(widget.postId))
      ..invalidate(commentsProvider(widget.postId))
      ..invalidate(commentSectionProvider('${widget.postId}|DISCUSSION'))
      ..invalidate(commentSectionProvider('${widget.postId}|SUBMISSION'));
  }

  Future<void> _submitAnswer(Post post) async {
    final sent = await showSubmitAnswerSheet(context, post);
    if (sent != true) return;
    _refresh();
    if (mounted) showMessage(context, 'Answer submitted.');
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
      _refresh();
      ref.invalidate(bountiesProvider);
      if (mounted) showMessage(context, 'Bounty awarded.');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
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
          final mine = me?.id == p.authorId;

          // A bounty thread keeps answers and chatter apart; an ordinary post
          // has only one kind of comment and does not need the split.
          return p.isBounty
              ? _BountyThread(
                  post: p,
                  canAccept: canAccept,
                  isAuthor: mine,
                  reply: _reply,
                  sending: _sending,
                  onSend: _send,
                  onAccept: _accept,
                  onSubmit: () => _submitAnswer(p),
                )
              : _PlainThread(
                  post: p,
                  reply: _reply,
                  sending: _sending,
                  onSend: _send,
                );
        },
      ),
    );
  }
}

/// An ordinary post: body, then one flat comment list.
class _PlainThread extends ConsumerWidget {
  const _PlainThread({
    required this.post,
    required this.reply,
    required this.sending,
    required this.onSend,
  });

  final Post post;
  final TextEditingController reply;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(commentsProvider(post.id));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
            children: [
              _PostBody(post: post),
              SectionHeader(title: 'Comments (${post.commentCount})'),
              comments.when(
                loading: () => const Loading(),
                error: (err, _) => ErrorView(error: err),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: EmptyState(
                          icon: Icons.mode_comment_outlined,
                          title: 'No comments yet',
                        ),
                      )
                    : Column(
                        children: [
                          for (final c in list) _CommentTile(comment: c),
                        ],
                      ),
              ),
            ],
          ),
        ),
        _ReplyBar(
          controller: reply,
          sending: sending,
          hint: 'Add a comment…',
          onSend: onSend,
        ),
      ],
    );
  }
}

/// A bounty: body, then Answers and Discussion as separate tabs.
///
/// The two lists answer different questions — "has anyone solved this" and
/// "what are people saying" — and merging them means the author has to read
/// the whole thread to find the two comments that matter.
class _BountyThread extends ConsumerWidget {
  const _BountyThread({
    required this.post,
    required this.canAccept,
    required this.isAuthor,
    required this.reply,
    required this.sending,
    required this.onSend,
    required this.onAccept,
    required this.onSubmit,
  });

  final Post post;
  final bool canAccept;
  final bool isAuthor;
  final TextEditingController reply;
  final bool sending;
  final VoidCallback onSend;
  final Future<void> Function(String commentId) onAccept;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissions =
        ref.watch(commentSectionProvider('${post.id}|SUBMISSION'));
    final discussion =
        ref.watch(commentSectionProvider('${post.id}|DISCUSSION'));

    final answerCount = submissions.valueOrNull?.length;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (_, _) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                    child: _PostBody(post: post),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeader(
                    TabBar(
                      tabs: [
                        Tab(
                          text: answerCount == null || answerCount == 0
                              ? 'Answers'
                              : 'Answers ($answerCount)',
                        ),
                        const Tab(text: 'Discussion'),
                      ],
                    ),
                    Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _SubmissionList(
                    state: submissions,
                    post: post,
                    canAccept: canAccept,
                    isAuthor: isAuthor,
                    onAccept: onAccept,
                    onSubmit: onSubmit,
                  ),
                  _DiscussionList(state: discussion),
                ],
              ),
            ),
          ),
          // The bar always writes discussion. Answers go through the composer,
          // because a submission must carry code, a sheet or a file and a
          // one-line field cannot express that.
          _ReplyBar(
            controller: reply,
            sending: sending,
            hint: 'Ask a question…',
            onSend: onSend,
          ),
        ],
      ),
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar, this.background);

  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double offset, bool overlaps) =>
      Container(color: background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarHeader old) =>
      old.tabBar != tabBar || old.background != background;
}

class _SubmissionList extends StatelessWidget {
  const _SubmissionList({
    required this.state,
    required this.post,
    required this.canAccept,
    required this.isAuthor,
    required this.onAccept,
    required this.onSubmit,
  });

  final AsyncValue<List<Comment>> state;
  final Post post;
  final bool canAccept;
  final bool isAuthor;
  final Future<void> Function(String commentId) onAccept;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return state.when(
      loading: () => const Loading(),
      error: (err, _) => ErrorView(error: err),
      data: (list) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          // The author cannot answer their own bounty — accept_bounty_solution
          // rejects it — so they get the rules instead of a dead button.
          if (post.isOpenBounty && !isAuthor)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FilledButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.upload_file, size: 17),
                label: Text('Submit an answer · ${post.bountyPoints} LP'),
              ),
            )
          else if (post.isOpenBounty && isAuthor)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _Notice(
                'Answers appear here. Accepting one pays out '
                '${post.bountyPoints} LP and closes the bounty.',
              ),
            ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No answers yet',
                message: post.isOpenBounty && !isAuthor
                    ? 'Be the first — the points are still on the table.'
                    : null,
              ),
            )
          else
            for (final c in list)
              _CommentTile(
                comment: c,
                onAccept: canAccept && c.authorId != post.authorId
                    ? () => onAccept(c.id)
                    : null,
              ),
        ],
      ),
    );
  }
}

class _DiscussionList extends StatelessWidget {
  const _DiscussionList({required this.state});

  final AsyncValue<List<Comment>> state;

  @override
  Widget build(BuildContext context) {
    return state.when(
      loading: () => const Loading(),
      error: (err, _) => ErrorView(error: err),
      data: (list) => list.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: EmptyState(
                icon: Icons.forum_outlined,
                title: 'Nothing discussed yet',
                message: 'Ask a clarifying question if the bounty is unclear.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              children: [for (final c in list) _CommentTile(comment: c)],
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.points.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.points.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.points),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
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
                FacultyChip(faculty: post.faculty, compact: true),
                if (post.isBounty) ...[
                  const SizedBox(width: 6),
                  PointsChip(points: post.bountyPoints),
                ],
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
              CodeHandoff(
                code: post.codeSnippet!,
                language: post.codeLanguage,
                title: _fileTitle(post),
              ),
            ],
            if (post.hasSheet) ...[
              const SizedBox(height: 14),
              SheetPreview(
                sheet: post.sheet!,
                title: _fileTitle(post),
                maxRows: 10,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Filenames come from the post text so a downloaded file is identifiable in
/// a Downloads folder next to five others. DocumentService sanitises it.
String _fileTitle(Post post) {
  final line = post.content.trim().split('\n').first.trim();
  if (line.isEmpty) return 'rtc-hub-${post.id.substring(0, 6)}';
  return line.length > 48 ? line.substring(0, 48) : line;
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

          // A submission carries its work with it. Code gets the same Run and
          // hand-off controls as a post, so the bounty author can check an
          // answer without leaving the thread.
          if (comment.hasCode) ...[
            const SizedBox(height: 10),
            CodeBlock(
              code: comment.codeSnippet!,
              language: comment.codeLanguage,
            ),
            CodeHandoff(
              code: comment.codeSnippet!,
              language: comment.codeLanguage,
              title: 'answer-${comment.id.substring(0, 6)}',
            ),
          ],
          if (comment.hasSheet) ...[
            const SizedBox(height: 10),
            SheetPreview(
              sheet: comment.sheet!,
              title: 'answer-${comment.id.substring(0, 6)}',
            ),
          ],
          if (comment.hasAttachment) ...[
            const SizedBox(height: 10),
            _AttachmentRow(comment: comment),
          ],

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

/// An uploaded file on a submission.
///
/// The URL is a signed one minted at upload time, so it can expire. Rather
/// than silently 400ing, the row opens it through the browser and lets the
/// platform report what happened.
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.comment});

  final Comment comment;

  IconData get _icon => switch (comment.attachmentKind) {
        'SHEET' => Icons.grid_on,
        'CODE' => Icons.terminal,
        _ => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final size = comment.attachmentSizeLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 17, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.attachmentName ?? 'Attachment',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (size != null)
                  Text(size, style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final url = comment.attachmentUrl;
              if (url == null) return;
              final ok = await launchUrlString(
                url,
                mode: LaunchMode.externalApplication,
              );
              if (!ok && context.mounted) {
                showMessage(context, 'Could not open that file.');
              }
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Open'),
          ),
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
