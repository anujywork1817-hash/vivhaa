import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../dashboard/presentation/widgets/match_card.dart';
import '../../../dashboard/presentation/widgets/section_header.dart';
import '../controllers/profile_detail_controller.dart';

/// "You may also like" — other members sharing the same religion or city,
/// shown below the main profile detail.
class SimilarProfilesSection extends ConsumerWidget {
  final String profileId;
  const SimilarProfilesSection({super.key, required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(similarProfilesProvider(profileId));

    return async.when(
      loading: () => SizedBox(
        height: 234,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, __) => ShimmerBox(
              width: 148, height: 220, borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (profiles) {
        if (profiles.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SectionHeader(title: 'You may also like'),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 234,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: profiles.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) => MatchCard(
                  profile: profiles[i],
                  width: 148,
                  onTap: () => context.push(AppRoutes.profileDetailPath(profiles[i].id)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
