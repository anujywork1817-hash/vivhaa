import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/admin_models.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../controllers/admin_controller.dart';

class AdminVerificationsScreen extends ConsumerWidget {
  const AdminVerificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(adminPendingVerificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Queue')),
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
              icon: Icons.verified_user_outlined,
              title: 'Nothing pending',
              message: 'All identity verification submissions have been reviewed.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminPendingVerificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _VerificationCard(request: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _VerificationCard extends ConsumerStatefulWidget {
  final AdminVerificationRequest request;
  const _VerificationCard({required this.request});

  @override
  ConsumerState<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends ConsumerState<_VerificationCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    final actions = ref.read(adminActionsProvider);
    if (approve) {
      await actions.approveVerification(widget.request.id);
    } else {
      await actions.rejectVerification(widget.request.id);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
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
          Text('Document: ${r.documentType}', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text('User: ${r.userId}',
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Image.network(
              r.documentUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: context.colors.line,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: context.colors.danger),
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
