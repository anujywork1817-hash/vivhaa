import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/conversation.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../controllers/chat_controller.dart';

enum ChatFilter { all, unread }

/// Which list the Chat tab is showing. Held outside the widget so the
/// choice survives tab switches.
final chatFilterProvider = StateProvider<ChatFilter>((ref) => ChatFilter.all);

/// Chat tab — conversations (all or unread only). A conversation exists
/// per profile whose interest was accepted in either direction. Call
/// history lives one tap away via the app bar's history icon
/// (CallHistoryScreen), not inline in this list.
class ChatTabScreen extends ConsumerWidget {
  const ChatTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(chatLiveUpdatesProvider);
    final filter = ref.watch(chatFilterProvider);
    final async = ref.watch(conversationsProvider);
    final unreadCount = async.valueOrNull?.where((c) => c.unreadCount > 0).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Call history',
            onPressed: () => context.push(AppRoutes.callHistory),
          ),
        ],
      ),
      body: Column(
        children: [
          // Horizontally scrollable so the pills can never overflow,
          // whatever the unread count grows to.
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
              children: [
                _FilterPill(
                  label: 'All',
                  selected: filter == ChatFilter.all,
                  onTap: () => ref.read(chatFilterProvider.notifier).state = ChatFilter.all,
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterPill(
                  label: 'Unread ($unreadCount)',
                  selected: filter == ChatFilter.unread,
                  onTap: () => ref.read(chatFilterProvider.notifier).state = ChatFilter.unread,
                ),
              ],
            ),
          ),
          Expanded(
            child: _ConversationsList(unreadOnly: filter == ChatFilter.unread),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? context.colors.ink : context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: selected ? context.colors.ink : context.colors.line),
        ),
        child: Text(
          label,
          style: context.textStyles.bodyMedium?.copyWith(
            color: selected ? Colors.white : context.colors.ink,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Time as the reference shows it: clock time today, "Yesterday", then a
/// date — a bare "3d" is much harder to place at a glance.
String _timestampLabel(DateTime t) {
  // The backend sends UTC (an RFC3339 timestamp with a "Z" suffix), so
  // t.hour/t.day/t.weekday read directly off it are UTC clock digits, not
  // what a member in India actually sees on their own clock — toLocal()
  // converts to the device's timezone (IST for every user this app is
  // built for) before any of those fields are read.
  final local = t.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final daysApart = today.difference(that).inDays;

  if (daysApart == 0) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'am' : 'pm'}';
  }
  if (daysApart == 1) return 'Yesterday';
  if (daysApart < 7) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[local.weekday - 1];
  }
  return '${local.day}/${local.month}/${local.year % 100}';
}

class _ConversationsList extends ConsumerWidget {
  final bool unreadOnly;
  const _ConversationsList({required this.unreadOnly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationsProvider);

    return async.when(
      loading: () => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, __) => ShimmerBox(
            width: double.infinity,
            height: 72,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
      ),
      error: (e, st) => ErrorStateView(
        failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
        onRetry: () => ref.invalidate(conversationsProvider),
      ),
      data: (all) {
        final conversations =
            unreadOnly ? all.where((c) => c.unreadCount > 0).toList() : all;

        if (conversations.isEmpty) {
          return EmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: unreadOnly ? 'Nothing unread' : 'No conversations yet',
            message: unreadOnly
                ? "You're all caught up."
                : 'Once you and a match both express interest, you can chat here.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(conversationsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: conversations.length,
            separatorBuilder: (_, __) => Divider(
                height: 1, indent: 84, color: context.colors.line),
            itemBuilder: (context, i) {
              final c = conversations[i];
              return _ConversationTile(
                conversation: c,
                timeLabel: _timestampLabel(c.lastMessageAt),
                onTap: () => context.push(AppRoutes.chatWindowPath(c.id)),
              );
            },
          ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String timeLabel;
  final VoidCallback onTap;

  const _ConversationTile(
      {required this.conversation, required this.timeLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount > 0 && !conversation.isBlocked;
    final profile = conversation.withProfile;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Opacity(
              opacity: conversation.isBlocked ? 0.5 : 1,
              child: ProfileAvatar(name: profile.name, size: 52, photoUrl: profile.photoSeed),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(profile.name,
                            style: context.textStyles.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (profile.verified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded, size: 14, color: context.colors.accent),
                      ],
                      if (conversation.isBlocked) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.block_rounded, size: 13, color: context.colors.danger),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conversation.isBlocked
                        ? 'Blocked'
                        : (conversation.lastMessage.isEmpty
                            ? 'Say hello 👋'
                            : conversation.lastMessage),
                    style: context.textStyles.bodySmall?.copyWith(
                      color: conversation.isBlocked
                          ? context.colors.danger
                          : (unread ? context.colors.ink : context.colors.muted),
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(timeLabel,
                    style: context.textStyles.bodySmall?.copyWith(
                      color: unread ? context.colors.success : context.colors.muted,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    )),
                const SizedBox(height: 6),
                if (unread)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: context.colors.success, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}',
                        maxLines: 1,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
