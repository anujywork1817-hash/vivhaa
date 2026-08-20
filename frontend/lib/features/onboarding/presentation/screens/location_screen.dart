import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/inputs/app_select_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../controllers/profile_creation_controller.dart';

const _states = [
  'Uttar Pradesh', 'Maharashtra', 'Tamil Nadu', 'Karnataka', 'Delhi-NCR', 'West Bengal',
  'Gujarat', 'Bihar', 'Madhya Pradesh', 'Andhra Pradesh', 'Punjab', 'Rajasthan',
];
const _citiesByState = {
  'Maharashtra': ['Mumbai', 'Pune', 'Nagpur', 'Thane', 'Nashik'],
};
const _defaultCities = ['Mumbai', 'Pune', 'Nagpur', 'Thane', 'Nashik'];
const _subCommunities = [
  '96 Kuli Maratha', 'Agri', 'Bhandari', 'Brahmin - Deshastha', 'Brahmin - Kokanastha',
  'Chambhar', 'Dhangar', 'Koli', 'Koshti', 'Kshatriya', 'Kunbi',
];

/// "Now let's build your Profile" — state, city, and sub-community.
class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final cities = _citiesByState[draft.state] ?? _defaultCities;

    final canContinue = draft.state != null && (draft.city ?? '').isNotEmpty;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 3,
      stepCount: onboardingStepCount,
      title: "Now let's build ${profileFor.possessive} Profile",
      headerIcon: Icons.location_on_rounded,
      onContinue: canContinue ? () => context.push(AppRoutes.maritalHeightDiet) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('State', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: 'State',
            hint: 'State you live in',
            value: draft.state,
            options: _states,
            onSelected: (v) => controller.update((p) => p.copyWith(state: v, city: null)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('City', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: 'City',
            hint: 'City you live in',
            value: draft.city,
            options: cities,
            onSelected: (v) => controller.update((p) => p.copyWith(city: v)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Sub-community', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: 'Sub-community',
            hint: 'Your Sub-community',
            value: draft.subCommunity,
            options: _subCommunities,
            onSelected: (v) => controller.update((p) => p.copyWith(subCommunity: v)),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: () =>
                controller.update((p) => p.copyWith(casteNoBar: !(p.casteNoBar ?? false))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: draft.casteNoBar ?? false,
                  onChanged: (v) => controller.update((p) => p.copyWith(casteNoBar: v ?? false)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      "Not particular about ${profileFor.possessive} partner's community (Caste no bar)",
                      style: context.textStyles.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
