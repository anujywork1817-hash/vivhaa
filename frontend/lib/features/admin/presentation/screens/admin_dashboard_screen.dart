import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../controllers/admin_controller.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load dashboard',
          message: 'Only accounts with the admin role can view this.',
        ),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminDashboardProvider),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 1.3,
                children: [
                  _StatTile(label: 'Total users', value: '${s.totalUsers}'),
                  _StatTile(label: 'Active users', value: '${s.activeUsers}'),
                  _StatTile(label: 'Suspended', value: '${s.suspendedUsers}'),
                  _StatTile(label: 'New signups today', value: '${s.newSignupsToday}'),
                  _StatTile(label: 'Total matches', value: '${s.totalMatches}'),
                  _StatTile(label: 'Total messages', value: '${s.totalMessages}'),
                  _StatTile(
                      label: 'Pending verifications',
                      value: '${s.pendingVerifications}',
                      highlight: s.pendingVerifications > 0),
                  _StatTile(
                      label: 'Pending reports',
                      value: '${s.pendingReports}',
                      highlight: s.pendingReports > 0),
                  _StatTile(label: 'Active subscriptions', value: '${s.activeSubscriptions}'),
                  _StatTile(label: 'Revenue', value: '₹${s.revenueInr}'),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _NavRow(
                icon: Icons.people_alt_outlined,
                label: 'Manage Users',
                onTap: () => context.push(AppRoutes.adminUsers),
              ),
              _NavRow(
                icon: Icons.verified_user_outlined,
                label: 'Verification Queue',
                badge: s.pendingVerifications,
                onTap: () => context.push(AppRoutes.adminVerifications),
              ),
              _NavRow(
                icon: Icons.flag_outlined,
                label: 'Reports Queue',
                badge: s.pendingReports,
                onTap: () => context.push(AppRoutes.adminReports),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _StatTile({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: highlight ? context.colors.accentSoft : context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: context.textStyles.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? badge;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.label, this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: context.colors.muted),
      title: Text(label, style: context.textStyles.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null && badge! > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: context.colors.accent, shape: BoxShape.circle),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          Icon(Icons.chevron_right_rounded, color: context.colors.muted),
        ],
      ),
      onTap: onTap,
    );
  }
}
