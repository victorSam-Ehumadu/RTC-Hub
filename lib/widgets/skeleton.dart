import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Content-shaped placeholders shown while a list loads.
///
/// The app used a centred spinner for every wait, which tells the user
/// nothing except that something is happening. A skeleton says *what* is
/// coming and how much of it, so the layout does not jump when the data
/// lands — the feed in particular went from a 36px dot to three full cards,
/// which reads as a flash of empty screen followed by a shove.
///
/// Deliberately not a package: `shimmer` would be a dependency for one
/// animation, and the pulse below is eight lines of it.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  /// `double.infinity` fills the parent, which is what most rows want.
  final double width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          // Sits between surface and outline, so it reads as "not yet
          // content" in every palette rather than as a filled element.
          color: Color.lerp(
            scheme.surface,
            scheme.outline,
            0.35 + 0.35 * _pulse.value,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// The shape of a [PostCard] before its data arrives.
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Skeleton(width: 40, height: 40, radius: 20),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Skeleton(width: 130, height: 11),
                    SizedBox(height: 6),
                    Skeleton(width: 90, height: 9),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Skeleton(width: double.infinity, height: 11),
            const SizedBox(height: 7),
            const Skeleton(width: double.infinity, height: 11),
            const SizedBox(height: 7),
            const Skeleton(width: 180, height: 11),
            const SizedBox(height: 14),
            Row(
              children: const [
                Skeleton(width: 54, height: 14),
                SizedBox(width: 16),
                Skeleton(width: 54, height: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A scrolling list of post skeletons. [count] is deliberately more than
/// fits: a list that ends above the fold looks like a finished, empty list.
class PostListSkeleton extends StatelessWidget {
  const PostListSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // The data is on its way, so let the placeholder be inert.
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const PostCardSkeleton(),
    );
  }
}

/// A list of simple rows — conversations, notifications, applicants.
class TileListSkeleton extends StatelessWidget {
  const TileListSkeleton({super.key, this.count = 6, this.hasAvatar = true});

  final int count;
  final bool hasAvatar;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: count,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (hasAvatar) ...[
              const Skeleton(width: 40, height: 40, radius: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Skeleton(width: 150, height: 11),
                  SizedBox(height: 7),
                  Skeleton(width: double.infinity, height: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shape of an opportunity card.
class OpportunityListSkeleton extends StatelessWidget {
  const OpportunityListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Skeleton(width: 200, height: 13),
              SizedBox(height: 9),
              Skeleton(width: 130, height: 10),
              SizedBox(height: 14),
              Skeleton(width: double.infinity, height: 9),
              SizedBox(height: 6),
              Skeleton(width: double.infinity, height: 9),
              SizedBox(height: 14),
              Row(
                children: [
                  Skeleton(width: 70, height: 22, radius: 11),
                  SizedBox(width: 8),
                  Skeleton(width: 54, height: 22, radius: 11),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile header placeholder.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Skeleton(width: 72, height: 72, radius: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Skeleton(width: 170, height: 15),
                  SizedBox(height: 9),
                  Skeleton(width: 120, height: 11),
                  SizedBox(height: 9),
                  Skeleton(width: 90, height: 11),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Skeleton(width: double.infinity, height: 11),
        const SizedBox(height: 7),
        const Skeleton(width: double.infinity, height: 11),
        const SizedBox(height: 7),
        const Skeleton(width: 220, height: 11),
        const SizedBox(height: 26),
        Row(
          children: const [
            Expanded(child: Skeleton(width: double.infinity, height: 62, radius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(width: double.infinity, height: 62, radius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(width: double.infinity, height: 62, radius: 12)),
          ],
        ),
      ],
    );
  }
}

/// A faculty marker.
///
/// Worth surfacing now that migration 0007 scopes content by faculty: it is
/// the difference between "this app shows me IT things" and "this app is
/// arbitrary", and in a mixed list — search results, a business feed, admin
/// views — it is the fastest way to tell two similar cards apart.
class FacultyChip extends StatelessWidget {
  const FacultyChip({super.key, required this.faculty, this.compact = false});

  /// Null means the post crosses both faculties, which is a real state and
  /// worth labelling rather than leaving blank.
  final String? faculty;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colour = facultyColor(faculty);
    final label = faculty == null ? 'ALL' : facultyLabel(faculty).toUpperCase();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: monoStyle(
          size: compact ? 9 : 9.5,
          weight: FontWeight.w700,
          color: colour,
        ),
      ),
    );
  }
}
