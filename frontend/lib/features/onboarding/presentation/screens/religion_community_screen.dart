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

const _religions = [
  'Hindu', 'Muslim', 'Christian', 'Sikh', 'Jain', 'Buddhist', 'Parsi', 'Jewish', 'No Religion'
];
const _communities = [
  'Brahmin', 'Rajput', 'Kayastha', 'Yadav', 'Reddy', 'Nair', 'Iyer', 'Sunni', 'Shia', 'Jat', 'Maratha', 'Other'
];
const _countries = [
  'India', 'United States', 'United Kingdom', 'Canada', 'Australia', 'United Arab Emirates',
  'Singapore', 'Other',
];

/// Right after name/DOB — religion, community, and country of residence.
class ReligionCommunityScreen extends ConsumerWidget {
  const ReligionCommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    final canContinue =
        draft.religion != null && draft.community != null && draft.country != null;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 2,
      stepCount: onboardingStepCount,
      title: '${profileFor.possessiveTitle} religion',
      headerIcon: Icons.diversity_3_rounded,
      onContinue: canContinue ? () => context.push(AppRoutes.locationDetails) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSelectField(
            label: 'Religion',
            value: draft.religion,
            options: _religions,
            onSelected: (v) => controller.update((p) => p.copyWith(religion: v)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Community', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppSelectField(
                  label: 'Community',
                  value: draft.community,
                  options: _communities,
                  onSelected: (v) => controller.update((p) => p.copyWith(community: v)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: context.colors.muted),
                  tooltip: 'Why we ask',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Why we ask for community'),
                      content: Text(
                          'Many members search and filter by community — adding ${profileFor.possessive} community makes ${profileFor.possessive} profile easier to find by people looking for a match within it.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Got it'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Living in', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: 'Living in',
            value: draft.country,
            options: _countries,
            onSelected: (v) => controller.update((p) => p.copyWith(country: v)),
          ),
        ],
      ),
    );
  }
}
