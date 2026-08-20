import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/app_notification.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../dashboard/presentation/controllers/dashboard_controller.dart';
import '../../../../core/exceptions/app_exception.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final hasUnread = (async.valueOrNull ?? const []).any((n) => !n.read);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () async {
                final result =
                    await ref.read(notificationsProvider.notifier).markAllAsRead();
                if (!context.mounted) return;
                result.when(
                  success: (_) {},
                  failure: (f) => ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(f.message))),
                );
              },
              child: Text(
                'Mark all as read',
                style: TextStyle(color: context.colors.accent),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, __) =>
              ShimmerBox(width: double.infinity, height: 64, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        ),
        error: (e, st) => ErrorStateView(
          failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Nothing yet',
              message: 'Interests, visitors, and match updates will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _NotificationTile(notification: notifications[i]),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  IconData get _icon => switch (notification.type) {
        NotificationType.interest => Icons.favorite_rounded,
        NotificationType.visitor => Icons.visibility_rounded,
        NotificationType.match => Icons.auto_awesome_rounded,
        NotificationType.message => Icons.chat_bubble_rounded,
        NotificationType.system => Icons.info_rounded,
      };

  String get _relativeTime {
    final diff = DateTime.now().difference(notification.timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: notification.read
          ? null
          : () => ref.read(notificationsProvider.notifier).markAsRead(notification.id),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: notification.read ? context.colors.surface : context.colors.accentSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: context.colors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: context.colors.bg,
              child: Icon(_icon, size: 18, color: context.colors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.title, style: context.textStyles.titleSmall),
                  const SizedBox(height: 3),
                  Text(notification.body,
                      style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                  const SizedBox(height: 6),
                  Text(_relativeTime,
                      style: context.textStyles.bodySmall?.copyWith(fontSize: 11)),
                ],
              ),
            ),
            if (!notification.read)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: context.colors.accent, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
