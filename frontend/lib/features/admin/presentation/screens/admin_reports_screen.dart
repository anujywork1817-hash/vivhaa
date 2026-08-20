import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/admin_models.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../controllers/admin_controller.dart';

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(adminPendingReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports Queue')),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load the queue',
          message: 'Try again in a moment.',
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.flag_outlined,
              title: 'Nothing pending',
              message: 'All member reports have been reviewed.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminPendingReportsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _ReportCard(report: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ReportCard extends ConsumerStatefulWidget {
  final AdminReport report;
  const _ReportCard({required this.report});

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  bool _busy = false;

  Future<void> _resolve(String status, {bool suspend = false}) async {
    setState(() => _busy = true);
    await ref.read(adminActionsProvider).resolveReport(widget.report.id, status, suspendUser: suspend);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reason: ${r.reason}', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text('Reported user: ${r.reportedUserId}',
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
          Text('Reported by: ${r.reporterUserId}',
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
          if (r.details != null && r.details!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(r.details!, style: context.textStyles.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _resolve('dismissed'),
                child: const Text('Dismiss'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _resolve('reviewed'),
                child: const Text('Mark reviewed'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: context.colors.danger),
                onPressed: _busy ? null : () => _resolve('action_taken', suspend: true),
                child: const Text('Suspend user'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
