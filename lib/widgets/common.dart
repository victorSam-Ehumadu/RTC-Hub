import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../core/theme.dart';
import '../data/errors.dart';
import '../models/profile.dart';

/// Avatar that falls back to initials, which is the common case early on when
/// nobody has uploaded a picture yet.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.profile, this.radius = 22});

  final Profile? profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = profile?.avatarUrl;
    final colour = roleColor(profile?.role);

    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colour.withValues(alpha: 0.2),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => _initials(colour),
            placeholder: (_, _) => _initials(colour),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colour.withValues(alpha: 0.2),
      child: _initials(colour),
    );
  }

  Widget _initials(Color colour) => Center(
        child: Text(
          profile?.initials ?? '?',
          style: TextStyle(
            color: colour,
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.7,
          ),
        ),
      );
}

/// Small coloured pill for a role, status or category.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) =>
      TagChip(label: role, color: roleColor(role));
}

/// Logic Points counter — monospace on purpose, so scores read as data.
class PointsChip extends StatelessWidget {
  const PointsChip({super.key, required this.points, this.compact = false});

  final int points;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.points.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.points.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, size: 14, color: AppColors.points),
          const SizedBox(width: 3),
          Text(
            compact ? '$points' : '$points LP',
            style: monoStyle(
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.points,
            ),
          ),
        ],
      ),
    );
  }
}

String formatTimeAgo(DateTime when) => timeago.format(when, locale: 'en_short');

/// What to show when a list comes back empty. Always offers the next action
/// rather than just stating there is nothing here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Error panel for a failed provider. Uses [describeError] so RLS rejections
/// read as "you do not have permission" rather than a Postgres code.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.danger),
            const SizedBox(height: 14),
            Text(
              describeError(error),
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: DottedProgressIndicator(size: 36),
        ),
      );
}

/// A ring of orbiting dots, in `AppColors.button`, used everywhere the app
/// used to show Material's stock arc spinner — busy buttons and full-page
/// loads alike, so every "working on it" moment reads the same way.
class DottedProgressIndicator extends StatefulWidget {
  const DottedProgressIndicator({
    super.key,
    this.size = 20,
    this.color = AppColors.button,
    this.dotCount = 8,
  });

  final double size;
  final Color color;
  final int dotCount;

  @override
  State<DottedProgressIndicator> createState() =>
      _DottedProgressIndicatorState();
}

class _DottedProgressIndicatorState extends State<DottedProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _DotsPainter(
              progress: _controller.value,
              color: widget.color,
              dotCount: widget.dotCount,
            ),
          ),
        ),
      );
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.progress,
    required this.color,
    required this.dotCount,
  });

  final double progress;
  final Color color;
  final int dotCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final dotRadius = radius / 5;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < dotCount; i++) {
      final t = i / dotCount;
      final angle = t * 2 * math.pi + progress * 2 * math.pi;
      final offset = Offset(
        center.dx + (radius - dotRadius) * math.cos(angle),
        center.dy + (radius - dotRadius) * math.sin(angle),
      );
      // Fades each dot around the ring so the rotation reads clearly.
      paint.color = color.withValues(alpha: 0.15 + 0.85 * t);
      canvas.drawCircle(offset, dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.dotCount != dotCount;
}

/// Section header used down the profile and admin screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: monoStyle(size: 11, weight: FontWeight.w700).copyWith(
                letterSpacing: 1.2,
                color:
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(describeError(error)),
      backgroundColor: AppColors.danger.withValues(alpha: 0.9),
    ));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
