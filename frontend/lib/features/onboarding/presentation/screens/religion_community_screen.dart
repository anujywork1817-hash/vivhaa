import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/inputs/app_searchable_select_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../../../reference/presentation/reference_providers.dart';
import '../controllers/profile_creation_controller.dart';

/// Right after name/DOB — religion, community, and country of residence.
///
/// All three lists come from `/reference/*` rather than the constants that
/// used to sit at the top of this file, so community cascades off religion
/// and the country list is the real one rather than eight entries plus
/// "Other".
class ReligionCommunityScreen extends ConsumerWidget {
  const ReligionCommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    final religionsAsync = ref.watch(religionsProvider);
    final countriesAsync = ref.watch(countriesProvider);
    final communities = ref.watch(communitiesProvider(draft.religion));

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
          AppSearchableSelectField(
            label: 'Religion',
            value: draft.religion,
            options: [
              for (final r in religionsAsync.valueOrNull ?? const [])
                SelectOption(r.name),
            ],
            isLoading: religionsAsync.isLoading,
            errorMessage: religionsAsync.hasError ? _listError : null,
            onRetry: () => ref.invalidate(religionsProvider),
            // Changing religion invalidates everything below it — a Hindu
            // profile switched to Muslim must not keep "Brahmin".
            onSelected: (o) => controller.update(
              (p) => p.copyWith(
                religion: o.value,
                clearCommunity: true,
                clearSubCommunity: true,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Community', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppSearchableSelectField(
                  label: 'Community',
                  value: draft.community,
                  enabled: draft.religion != null,
                  emptyMessage: 'Choose a religion first',
                  options: [for (final c in communities) SelectOption(c.name)],
                  isLoading: religionsAsync.isLoading,
                  onSelected: (o) => controller.update(
                    (p) => p.copyWith(community: o.value, clearSubCommunity: true),
                  ),
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
          AppSearchableSelectField(
            label: 'Living in',
            hint: 'Country you live in',
            value: draft.country,
            options: [
              for (final c in countriesAsync.valueOrNull ?? const [])
                SelectOption(c.name, c.label),
            ],
            isLoading: countriesAsync.isLoading,
            errorMessage: countriesAsync.hasError ? _listError : null,
            onRetry: () => ref.invalidate(countriesProvider),
            // State and city are keyed by country, so both have to go.
            onSelected: (o) => controller.update(
              (p) => p.copyWith(country: o.value, clearState: true, clearCity: true),
            ),
          ),
        ],
      ),
    );
  }
}

const _listError = "Couldn't load this list. Check your connection and try again.";
