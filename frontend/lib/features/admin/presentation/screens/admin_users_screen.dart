import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/admin_models.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../controllers/admin_controller.dart';

const _statusFilters = [null, 'active', 'suspended', 'pending'];

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider);
    final statusFilter = ref.watch(adminUserStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by phone or email',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                  ),
                  onSubmitted: (v) => ref.read(adminUserSearchProvider.notifier).state = v,
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _statusFilters.map((status) {
                      final selected = statusFilter == status;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(status ?? 'All'),
                          selected: selected,
                          onSelected: (_) =>
                              ref.read(adminUserStatusFilterProvider.notifier).state = status,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load users',
                message: 'Try again in a moment.',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'No users found',
                    message: 'Try a different search or filter.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(adminUsersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _UserRow(user: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  final AdminUser user;
  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suspended = user.status == 'suspended';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.email ?? user.phone ?? user.id,
                    style: context.textStyles.titleSmall, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${user.role} · ${user.status}',
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: suspended ? context.colors.success : context.colors.danger,
            ),
            onPressed: () async {
              final actions = ref.read(adminActionsProvider);
              if (suspended) {
                await actions.activateUser(user.id);
              } else {
                await actions.suspendUser(user.id);
              }
            },
            child: Text(suspended ? 'Activate' : 'Suspend'),
          ),
        ],
      ),
    );
  }
}
