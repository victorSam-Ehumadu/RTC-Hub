import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

/// Prepares a video for upload — §2.8.
///
/// The brief is unusually direct here: *"uploaded videos must be compressed
/// or transcoded before storage. Thumbnail generation is required. Raw,
/// unprocessed video uploads dumped directly to storage are not
/// acceptable."*
///
/// So this does three things before anything reaches Supabase: transcode to
/// a smaller H.264 file, pull a poster frame, and report the saving. The
/// saving is surfaced in the UI rather than kept as a log line, because it
/// is also the evidence that the processing happened — a demo needs to be
/// able to point at it.
///
/// Processing on-device rather than server-side is deliberate. Supabase has
/// no transcoding primitive, an Edge Function would have to receive the raw
/// file first (which is the thing being avoided), and a phone already has a
/// hardware encoder sitting idle. The cost is that the user waits, so
/// [compress] streams progress.
class VideoService {
  const VideoService();

  /// Anything longer is a different product. §2.4 asks for "short-form"
  /// content; an unbounded limit also means unbounded transcode time on a
  /// mid-range phone.
  static const maxDuration = Duration(minutes: 3);

  /// Picks a video from the gallery or camera, capped at [maxDuration].
  Future<File?> pick({bool fromCamera = false}) async {
    final picked = await ImagePicker().pickVideo(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: maxDuration,
    );
    return picked == null ? null : File(picked.path);
  }

  /// Transcodes [source] and returns the processed file plus its poster
  /// frame.
  ///
  /// [onProgress] receives 0–100. Transcoding a two-minute clip takes tens
  /// of seconds on a mid-range device, which is far too long to show an
  /// indeterminate spinner over.
  Future<ProcessedVideo> compress(
    File source, {
    void Function(double percent)? onProgress,
  }) async {
    final subscription =
        VideoCompress.compressProgress$.subscribe((p) => onProgress?.call(p));

    try {
      final original = await source.length();

      final info = await VideoCompress.compressVideo(
        source.path,
        quality: VideoQuality.MediumQuality,
        // Keep the user's original. Deleting it would be a surprising thing
        // for a social app to do to someone's camera roll.
        deleteOrigin: false,
        includeAudio: true,
      );

      final path = info?.path;
      if (path == null) {
        throw const ProcessingFailure('The video could not be processed.');
      }

      // A poster frame, so the feed shows something other than a black
      // rectangle before playback starts.
      final thumbnail = await VideoCompress.getFileThumbnail(
        source.path,
        quality: 70,
        position: -1, // let the plugin choose a representative frame
      );

      final processed = File(path);
      return ProcessedVideo(
        video: processed,
        thumbnail: thumbnail,
        originalBytes: original,
        processedBytes: await processed.length(),
        duration: info?.duration == null
            ? null
            : Duration(seconds: info!.duration!.round()),
      );
    } finally {
      // A plain VoidCallback, not a Future — the plugin's Subscription is
      // its own type rather than a StreamSubscription.
      subscription.unsubscribe();
    }
  }

  /// Frees the plugin's scratch files. Worth calling once a post is sent —
  /// transcoded videos are large and otherwise sit in the cache until
  /// Android decides to reclaim them.
  Future<void> cleanUp() => VideoCompress.deleteAllCache();

  /// Cancels an in-flight transcode.
  Future<void> cancel() => VideoCompress.cancelCompression();
}

class ProcessedVideo {
  const ProcessedVideo({
    required this.video,
    required this.originalBytes,
    required this.processedBytes,
    this.thumbnail,
    this.duration,
  });

  final File video;
  final File? thumbnail;
  final int originalBytes;
  final int processedBytes;
  final Duration? duration;

  /// How much smaller the processed file is, as a percentage. Shown to the
  /// user, and the demonstrable part of "compressed before storage".
  int get savingPercent {
    if (originalBytes <= 0) return 0;
    final saved = (1 - processedBytes / originalBytes) * 100;
    return saved.isFinite ? saved.round().clamp(0, 99) : 0;
  }

  String get summary {
    String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
    return '${mb(originalBytes)} MB → ${mb(processedBytes)} MB '
        '($savingPercent% smaller)';
  }
}

class ProcessingFailure implements Exception {
  const ProcessingFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
