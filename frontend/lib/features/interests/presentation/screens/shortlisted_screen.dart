import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../dashboard/presentation/widgets/recommended_list_tile.dart';
import '../controllers/shortlisted_list_controller.dart';

/// Lists every profile the user has bookmarked/shortlisted (the bookmark
/// icon on the Matches tab's cards) — this screen was the missing half of
/// that feature: the toggle worked and round-tripped through the backend,
/// but there was previously nowhere to ever see the resulting list.
class ShortlistedScreen extends ConsumerWidget {
  const ShortlistedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortlisted = ref.watch(shortlistedListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shortlisted')),
      body: shortlisted.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: 'Could not load your shortlist. Pull to refresh to try again.',
        ),
        data: (profiles) {
          if (profiles.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'No shortlisted profiles yet',
              message: 'Profiles you bookmark on the Matches tab will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(shortlistedListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final profile = profiles[index];
                return RecommendedListTile(
                  profile: profile,
                  onTap: () => context.push(AppRoutes.profileDetailPath(profile.id)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
