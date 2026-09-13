import io

# ── Provider ────────────────────────────────────────────────────────────
p = 'lib/providers.dart'
s = io.open(p, encoding='utf-8').read()
s = s.replace(
    "import 'data/storage_repository.dart';",
    "import 'data/storage_repository.dart';\nimport 'data/video_service.dart';",
    1,
)
s = s.replace(
    "final documentServiceProvider = Provider((_) => const DocumentService());",
    "final documentServiceProvider = Provider((_) => const DocumentService());\n"
    "\n"
    "/// Transcoding and thumbnail generation for short-form video (§2.8).\n"
    "final videoServiceProvider = Provider((_) => const VideoService());",
    1,
)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('providers: videoServiceProvider')


# ── Composer: pick, process, upload ─────────────────────────────────────
p = 'lib/features/feed/create_post_screen.dart'
s = io.open(p, encoding='utf-8').read()

s = s.replace(
    "  SheetDoc? _sheet;\n  bool _busy = false;",
    "  SheetDoc? _sheet;\n"
    "  ProcessedVideo? _video;\n"
    "  double _videoProgress = 0;\n"
    "  bool _processingVideo = false;\n"
    "  bool _busy = false;",
    1,
)

old = "  Future<void> _submit() async {"
new = '''  /// Picks a clip and processes it before it goes anywhere near storage.
  ///
  /// §2.8 rejects raw uploads outright, so compression and thumbnail
  /// generation happen here, on the device, while the user waits — and the
  /// size saving is shown back to them so the processing is visible rather
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

  Future<void> _submit() async {'''
assert old in s, 'submit anchor'
s = s.replace(old, new, 1)

# Upload the processed files, then post.
old = """    setState(() => _busy = true);
    try {
      await ref.read(postRepoProvider).create("""
new = """    setState(() => _busy = true);
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

      await ref.read(postRepoProvider).create("""
assert old in s, 'submit body anchor'
s = s.replace(old, new, 1)

old = """            sheetData: _canSheet ? _sheet?.toMap() : null,
            sheetName: _canSheet ? _sheet?.name : null,
          );"""
new = """            sheetData: _canSheet ? _sheet?.toMap() : null,
            sheetName: _canSheet ? _sheet?.name : null,
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
          );

      // The transcoded copy is large and would otherwise sit in the cache
      // until Android decided to reclaim it.
      await ref.read(videoServiceProvider).cleanUp();"""
assert old in s, 'create call anchor'
s = s.replace(old, new, 1)

# Post type follows the attachment.
old = """            type: _isBounty
                ? 'BOUNTY'
                : (_attachCode ? 'CODE' : 'TEXT'),"""
new = """            type: _isBounty
                ? 'BOUNTY'
                : _video != null
                    ? 'VIDEO'
                    : (_attachCode ? 'CODE' : 'TEXT'),"""
assert old in s, 'type anchor'
s = s.replace(old, new, 1)

# ── the video section in the form ───────────────────────────────────────
old = "            if (canAttachSheet) ...["
new = """            // §2.4 asks students and alumni for short-form video. A
            // business posting a recruitment clip is the same feature, so
            // the only gate is that bounties are not video posts.
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

            if (canAttachSheet) ..."""
assert old in s, 'sheet gate anchor'
s = s.replace(old, new, 1)
s = s.replace("if (canAttachSheet) ...\n            const SectionHeader(title: 'Spreadsheet'),",
              "if (canAttachSheet) ...[\n            const SectionHeader(title: 'Spreadsheet'),", 1)

# ── the widget ──────────────────────────────────────────────────────────
s = s.rstrip() + '''

/// Pick / record / processing state for the video attachment.
///
/// The compression figure is deliberately prominent: it is what makes
/// "compressed before storage" demonstrable rather than asserted, and it
/// also tells the user why they waited.
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
                        fontSize: 13, fontWeight: FontWeight.w600),
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
                    Icon(Icons.check_circle,
                        size: 14, color: AppColors.success),
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
                Text(video!.summary,
                    style: monoStyle(size: 11, color: muted)),
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
'''

if "import '../../data/video_service.dart';" not in s:
    s = s.replace("import '../../models/sheet.dart';",
                  "import '../../data/video_service.dart';\nimport '../../models/sheet.dart';", 1)

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('create_post_screen: video attachment')
