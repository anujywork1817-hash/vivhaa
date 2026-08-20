import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/visitor_record.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../controllers/visitors_controller.dart';

class VisitorsScreen extends ConsumerWidget {
  const VisitorsScreen({super.key});

  String _relativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitors = ref.watch(visitorsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile Visitors')),
      body: visitors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: 'Could not load your visitors. Pull to refresh to try again.',
        ),
        data: (records) {
          if (records.isEmpty) {
            return const EmptyState(
              icon: Icons.visibility_outlined,
              title: 'No visitors yet',
              message: 'Members who view your profile will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(visitorsListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _VisitorTile(
                record: records[index],
                timeLabel: _relativeTime(records[index].visitedAt),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VisitorTile extends StatelessWidget {
  final VisitorRecord record;
  final String timeLabel;
  const _VisitorTile({required this.record, required this.timeLabel});

  @override
  Widget build(BuildContext context) {
    final profile = record.profile;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: profile.id.isEmpty
          ? null
          : () => context.push(AppRoutes.profileDetailPath(profile.id)),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: context.colors.line),
        ),
        child: Row(
          children: [
            ProfileAvatar(name: profile.name, size: 52, borderRadius: BorderRadius.circular(12)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name,
                      style: context.textStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(profile.city,
                      style: context.textStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(timeLabel,
                style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
