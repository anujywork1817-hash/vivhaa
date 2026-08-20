import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../dashboard/presentation/widgets/recommended_list_tile.dart';
import '../controllers/favourites_controller.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourites = ref.watch(favouritesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      body: favourites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: 'Could not load your favourites. Pull to refresh to try again.',
        ),
        data: (profiles) {
          if (profiles.isEmpty) {
            return const EmptyState(
              icon: Icons.star_border_rounded,
              title: 'No favourites yet',
              message: 'Profiles you mark as a favourite will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(favouritesListProvider),
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
