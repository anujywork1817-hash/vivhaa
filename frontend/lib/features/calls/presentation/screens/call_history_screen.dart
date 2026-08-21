import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/call_history_entry.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../controllers/call_controller.dart';
import '../controllers/call_history_controller.dart';
import 'active_call_screen.dart';

/// Time as the call log shows it — same convention as the chat tab's
/// _timestampLabel (clock time today, "Yesterday", weekday, then a date).
String _timestampLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final daysApart = today.difference(that).inDays;

  if (daysApart == 0) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'am' : 'pm'}';
  }
  if (daysApart == 1) return 'Yesterday';
  if (daysApart < 7) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[t.weekday - 1];
  }
  return '${t.day}/${t.month}/${t.year % 100}';
}

String _durationLabel(int seconds) {
  final d = Duration(seconds: seconds);
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// WhatsApp-style call log: past calls with the partner's avatar, a
/// direction/status icon, whether it was video or voice, a relative
/// timestamp, and duration if the call connected. Tapping a row
/// re-initiates a call to that partner via the same CallController flow
/// the chat window uses.
class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(callHistoryControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _callBack(CallHistoryEntry entry, {required bool isVideo}) async {
    if (ref.read(callControllerProvider).isActive) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("You're already on a call.")));
      return;
    }
    await ref.read(callControllerProvider.notifier).startCall(
          peerUserId: entry.partnerUserId,
          peerName: entry.partnerName,
          peerPhotoUrl: entry.partnerPhoto,
          isVideo: isVideo,
        );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Call History')),
      body: _body(state),
    );
  }

  Widget _body(CallHistoryState state) {
    if (state.loading && state.entries.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, __) => ShimmerBox(
            width: double.infinity,
            height: 64,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
      );
    }

    if (state.failure != null && state.entries.isEmpty) {
      return ErrorStateView(
        failure: state.failure!,
        onRetry: () => ref.read(callHistoryControllerProvider.notifier).refresh(),
      );
    }

    if (state.entries.isEmpty) {
      return const EmptyState(
        icon: Icons.call_outlined,
        title: 'No calls yet',
        message: 'Voice and video calls with your matches will show up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(callHistoryControllerProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: state.entries.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) =>
            Divider(height: 1, indent: 84, color: context.colors.line),
        itemBuilder: (context, i) {
          if (i >= state.entries.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final entry = state.entries[i];
          return _CallHistoryTile(
            entry: entry,
            onTap: () => _callBack(entry, isVideo: entry.isVideo),
          );
        },
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  final CallHistoryEntry entry;
  final VoidCallback onTap;

  const _CallHistoryTile({required this.entry, required this.onTap});

  bool get _isMissed =>
      entry.direction == CallDirection.incoming &&
      (entry.status == CallStatusHistory.missed || entry.status == CallStatusHistory.rejected);

  IconData get _directionIcon {
    if (entry.status == CallStatusHistory.failed) return Icons.call_end_rounded;
    if (_isMissed) return Icons.call_missed_rounded;
    return entry.direction == CallDirection.outgoing
        ? Icons.call_made_rounded
        : Icons.call_received_rounded;
  }

  String get _statusLabel {
    switch (entry.status) {
      case CallStatusHistory.missed:
        return entry.direction == CallDirection.incoming ? 'Missed call' : 'No answer';
      case CallStatusHistory.rejected:
        return entry.direction == CallDirection.incoming ? 'Declined' : 'Call declined';
      case CallStatusHistory.failed:
        return 'Call failed';
      case CallStatusHistory.initiated:
        return 'Not connected';
      case CallStatusHistory.ongoing:
      case CallStatusHistory.completed:
        return entry.durationSeconds != null && entry.durationSeconds! > 0
            ? _durationLabel(entry.durationSeconds!)
            : (entry.direction == CallDirection.outgoing ? 'Outgoing call' : 'Incoming call');
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isMissed || entry.status == CallStatusHistory.failed
        ? context.colors.danger
        : context.colors.muted;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            ProfileAvatar(name: entry.partnerName, size: 52, photoUrl: entry.partnerPhoto),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.partnerName,
                      style: context.textStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(_directionIcon, size: 15, color: statusColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _statusLabel,
                          style: context.textStyles.bodySmall?.copyWith(color: statusColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_timestampLabel(entry.startedAt),
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                const SizedBox(height: 6),
                Icon(
                  entry.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 18,
                  color: context.colors.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
