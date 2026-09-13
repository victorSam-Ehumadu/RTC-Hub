import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/theme.dart';

/// A short-form video on a post (§2.4).
///
/// Starts as the thumbnail generated at upload time and only creates a
/// player once tapped. A feed with five autoplaying videos is a feed that
/// eats a student's data bundle, and §2.4's framing — "day-in-the-life
/// content, career journey stories" — is content people choose to watch,
/// not wallpaper.
class VideoView extends StatefulWidget {
  const VideoView({
    super.key,
    required this.url,
    this.thumbnailUrl,
    this.aspectRatio = 9 / 16,
    this.autoplayOnTap = true,
  });

  final String url;
  final String? thumbnailUrl;

  /// Portrait by default: this is phone-shot footage.
  final double aspectRatio;

  final bool autoplayOnTap;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_controller != null) {
      // Second tap pauses rather than restarting, which is what a tap on a
      // playing video means everywhere else.
      setState(() {
        _controller!.value.isPlaying
            ? _controller!.pause()
            : _controller!.play();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      if (widget.autoplayOnTap) await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This video could not be played.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        // Once the real dimensions are known, use them — a portrait clip in
        // a landscape box is letterboxed twice over.
        aspectRatio: ready ? _controller!.value.aspectRatio : widget.aspectRatio,
        child: GestureDetector(
          onTap: _start,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ready)
                VideoPlayer(_controller!)
              else if (widget.thumbnailUrl != null)
                CachedNetworkImage(
                  imageUrl: widget.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const ColoredBox(
                    color: Colors.black26,
                    child: Icon(Icons.videocam_off_outlined, size: 32),
                  ),
                )
              else
                const ColoredBox(color: Colors.black45),

              if (!ready)
                Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              size: 34, color: Colors.white),
                        ),
                ),

              if (ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: AppColors.accent,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),

              if (_error != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    color: Colors.black54,
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
