import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationRepoProvider).markAllRead();
              ref
                ..invalidate(notificationsProvider)
                ..invalidate(unreadCountProvider);
            },
            child: const Text('Mark all read'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: notifications.when(
          loading: () => const TileListSkeleton(),
          error: (err, _) => ErrorView(
            error: err,
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: const EmptyState(
                      icon: Icons.notifications_none,
                      title: 'Nothing here yet',
                      message:
                          'Reactions, answers, connection requests and admin '
                          'announcements land here.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) =>
                  _NotificationTile(notification: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, colour) = _look(notification.type);

    return ListTile(
      tileColor: notification.read
          ? null
          : AppColors.accent.withValues(alpha: 0.05),
      leading: CircleAvatar(
        radius: 19,
        backgroundColor: colour.withValues(alpha: 0.15),
        child: Icon(icon, size: 19, color: colour),
      ),
      title: Text(
        notification.title,
        style: TextStyle(
          fontSize: 14,
          fontWeight:
              notification.read ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
      subtitle: notification.body == null
          ? null
          : Text(
              notification.body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Text(
        formatTimeAgo(notification.createdAt),
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
      onTap: () async {
        if (!notification.read) {
          await ref.read(notificationRepoProvider).markRead(notification.id);
          ref
            ..invalidate(notificationsProvider)
            ..invalidate(unreadCountProvider);
        }
        if (!context.mounted) return;

        // Route to whatever the notification is about.
        final postId = notification.postId;
        final senderId = notification.senderId;
        if (postId != null) {
          context.push('/post/$postId');
        } else if (notification.type == 'NEW_MESSAGE' && senderId != null) {
          context.push('/chat/$senderId');
        } else if (notification.type == 'CONNECTION_REQUEST') {
          context.go('/messages');
        } else if (notification.opportunityId != null) {
          context.go('/opportunities');
        }
      },
    );
  }

  static (IconData, Color) _look(String type) => switch (type) {
        'POST_REACTION' => (Icons.favorite, AppColors.danger),
        'POST_COMMENT' => (Icons.mode_comment, roleColor('STUDENT')),
        'NEW_MESSAGE' => (Icons.forum, roleColor('STUDENT')),
        'CONNECTION_REQUEST' => (Icons.person_add, roleColor('ALUMNI')),
        'CONNECTION_ACCEPTED' => (Icons.people, AppColors.accent),
        'BOUNTY_SOLVED' => (Icons.bolt, AppColors.points),
        'SKILL_ENDORSED' => (Icons.verified, AppColors.accent),
        'OPPORTUNITY_MATCH' => (Icons.work, AppColors.accent),
        'ADMIN_ANNOUNCEMENT' => (Icons.campaign, AppColors.points),
        'ACCOUNT_APPROVED' => (Icons.verified_user, AppColors.accent),
        'ACCOUNT_SUSPENDED' => (Icons.gpp_bad, AppColors.danger),
        _ => (Icons.notifications, AppColors.darkMuted),
      };
}
