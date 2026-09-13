import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../data/video_service.dart';
import '../../models/sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/sheet_preview.dart';

/// Composer for a normal post or a bounty.
///
/// The bounty value is not settable here on purpose: `trg_posts_guard` sets every
/// new bounty to 10 points, and `escalate_bounties()` raises unsolved ones
/// over time, so there is nothing for the client to decide.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.asBounty = false});

  final bool asBounty;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _content = TextEditingController();
  final _code = TextEditingController();
  final _module = TextEditingController();

  late bool _isBounty = widget.asBounty;
  bool _attachCode = false;
  String _language = 'dart';
  SheetDoc? _sheet;
  ProcessedVideo? _video;
  double _videoProgress = 0;
  bool _processingVideo = false;
  bool _busy = false;

  @override
  void dispose() {
    _content.dispose();
    _code.dispose();
    _module.dispose();
    super.dispose();
  }

  /// Attaches a spreadsheet the author built in Excel or Sheets.
  ///
  /// There is no in-app grid editor on purpose: Excel already is one, it
  /// recalculates formulas, and every Business student has it. The app's job
  /// is to carry the file and preview it, not to reimplement it.
  Future<void> _importSheet() async {
    try {
      final docs = ref.read(documentServiceProvider);
      final picked = await docs.pickAttachment(extensions: ['xlsx', 'csv']);
      if (picked?.path == null || !mounted) return;

      final doc = await docs.readSheet(File(picked!.path!));
      if (!mounted) return;
      setState(() => _sheet = doc);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// The same gate `build` applies, read where `_submit` can see it. Keeping
  /// one source of truth would mean threading state through; re-deriving it
  /// from the profile is cheaper and cannot drift.
  String? get _facultyForPosting => ref.read(meProvider)?.postingFaculty;
  bool get _canCode => _facultyForPosting == null || _facultyForPosting == 'IT';
  bool get _canSheet =>
      _facultyForPosting == null || _facultyForPosting == 'BUSINESS';

  /// Picks a clip and processes it before it goes anywhere near storage.
  ///
  /// §2.8 rejects raw uploads outright, so compression and thumbnail
  /// generation happen here, on the device, while the user waits — and the
  /// size saving is shown back to them, so the processing is visible rather
  /// than merely claimed.
  Future<void> _attachVideo({bool fromCamera = false}) async {
    final service = ref.read(videoServiceProvider);
    try {
      final picked = await service.pick(fromCamera: fromCamera);
      if (picked == null || !mounted) return;

      setState(() {
        _processingVideo = true;
        _videoProgress = 0;
      });

      final processed = await service.compress(
        picked,
        onProgress: (percent) {
          if (mounted) setState(() => _videoProgress = percent);
        },
      );
      if (!mounted) return;
      setState(() {
        _video = processed;
        _processingVideo = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _processingVideo = false);
      showError(context, error);
    }
  }

  Future<void> _submit() async {
    if (_content.text.trim().isEmpty) {
      showMessage(context, 'Write something first.');
      return;
    }
    setState(() => _busy = true);
    try {
      String? videoUrl;
      String? thumbnailUrl;

      if (_video != null) {
        final storage = ref.read(storageRepoProvider);
        videoUrl = await storage.uploadPostMedia(_video!.video);
        if (_video!.thumbnail != null) {
          thumbnailUrl = await storage.uploadPostMedia(_video!.thumbnail!);
        }
      }

      await ref
          .read(postRepoProvider)
          .create(
            content: _content.text,
            type: _isBounty
                ? 'BOUNTY'
                : _video != null
                ? 'VIDEO'
                : (_attachCode ? 'CODE' : 'TEXT'),
            codeLanguage: _canCode && _attachCode ? _language : null,
            codeSnippet: _canCode && _attachCode && _code.text.trim().isNotEmpty
                ? _code.text
                : null,
            isBounty: _isBounty,
            bountyModule: _isBounty && _module.text.trim().isNotEmpty
                ? _module.text.trim()
                : null,
            sheetData: _canSheet ? _sheet?.toMap() : null,
            sheetName: _canSheet ? _sheet?.name : null,
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
          );

      // The transcoded copy is large and would otherwise sit in the cache
      // until Android decided to reclaim it.
      await ref.read(videoServiceProvider).cleanUp();

      ref.invalidate(feedProvider);
      ref.invalidate(bountiesProvider);

      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        _isBounty ? 'Bounty posted — 10 LP on offer.' : 'Posted.',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);

    // Which attachment this author gets. A student or alumnus is bound to
    // their faculty; a business posting to one cohort follows that cohort;
    // anyone spanning both (admin, a business recruiting both) gets both.
    final faculty = me?.postingFaculty;
    final canAttachCode = faculty == null || faculty == 'IT';
    final canAttachSheet = faculty == null || faculty == 'BUSINESS';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isBounty ? 'Post a bounty' : 'New post'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const DottedProgressIndicator(size: 16)
                : const Text('Post'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isBounty,
              onChanged: (v) => setState(() {
                _isBounty = v;
                // Only pre-open the snippet box for someone who can use it;
                // a Business bounty wants a spreadsheet, not Java.
                if (v && canAttachCode) _attachCode = true;
              }),
              title: const Text('Ask as a bounty'),
              subtitle: Text(
                'Offers 10 Logic Points to whoever solves it. You pick the '
                'accepted answer.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              secondary: const Icon(Icons.bolt, color: AppColors.points),
            ),
            const Divider(height: 24),

            TextField(
              controller: _content,
              maxLines: 6,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isBounty
                    ? 'What are you stuck on? Describe what you expected and '
                          'what actually happened.'
                    : 'Share what you are building…',
              ),
            ),

            if (_isBounty) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _module,
                decoration: const InputDecoration(
                  labelText: 'Module (optional)',
                  hintText: 'e.g. Advanced Java',
                  prefixIcon: Icon(Icons.school_outlined, size: 20),
                ),
              ),
            ],

            if (canAttachCode) ...[
              const SectionHeader(title: 'Code'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _attachCode,
                onChanged: (v) => setState(() => _attachCode = v),
                title: const Text('Attach a snippet'),
                secondary: const Icon(Icons.code),
              ),

              if (_attachCode) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: [
                    for (final lang in kCodeLanguages)
                      DropdownMenuItem(value: lang, child: Text(lang)),
                  ],
                  onChanged: (v) => setState(() => _language = v ?? 'dart'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  maxLines: 14,
                  minLines: 6,
                  style: monoStyle(size: 13),
                  decoration: const InputDecoration(
                    hintText: 'Paste your code here',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ],

            // §2.4 asks students and alumni for short-form video. A
            // business recruitment clip is the same feature, so the only
            // gate is that a bounty is a question, not a video post.
            if (!_isBounty) ...[
              const SectionHeader(title: 'Video'),
              _VideoAttachment(
                video: _video,
                processing: _processingVideo,
                progress: _videoProgress,
                onPick: () => _attachVideo(),
                onRecord: () => _attachVideo(fromCamera: true),
                onRemove: () => setState(() => _video = null),
              ),
            ],

            if (canAttachSheet) ...[
              const SectionHeader(title: 'Spreadsheet'),
              if (_sheet == null)
                OutlinedButton.icon(
                  onPressed: _importSheet,
                  icon: const Icon(Icons.upload_file, size: 17),
                  label: const Text('Attach a .xlsx or .csv'),
                )
              else ...[
                SheetPreview(
                  sheet: _sheet!,
                  title: _content.text.trim().isEmpty
                      ? 'sheet'
                      : _content.text.trim(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _importSheet,
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Replace'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _sheet = null),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Pick / record / processing state for the video attachment.
///
/// The compression figure is deliberately prominent: it is what makes
/// "compressed before storage" demonstrable rather than asserted, and it
/// tells the user why they waited.
class _VideoAttachment extends StatelessWidget {
  const _VideoAttachment({
    required this.video,
    required this.processing,
    required this.progress,
    required this.onPick,
    required this.onRecord,
    required this.onRemove,
  });

  final ProcessedVideo? video;
  final bool processing;
  final double progress;
  final VoidCallback onPick;
  final VoidCallback onRecord;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    if (processing) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.movie_filter_outlined, size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compressing — ${progress.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress <= 0 ? null : progress / 100,
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Transcoding on your phone so the upload is small. This is the '
              'slow part.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: muted),
            ),
          ],
        ),
      );
    }

    if (video == null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.video_library_outlined, size: 17),
              label: const Text('Choose'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRecord,
              icon: const Icon(Icons.videocam_outlined, size: 17),
              label: const Text('Record'),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (video!.thumbnail != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                video!.thumbnail!,
                width: 46,
                height: 62,
                fit: BoxFit.cover,
              ),
            )
          else
            const Icon(Icons.movie_outlined, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      'Processed',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(video!.summary, style: monoStyle(size: 11, color: muted)),
                if (video!.duration != null)
                  Text(
                    '${video!.duration!.inSeconds}s · thumbnail generated',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close, size: 18, color: muted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
