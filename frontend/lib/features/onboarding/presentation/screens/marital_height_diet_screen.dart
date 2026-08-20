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

const _maritalOptions = ['Never Married', 'Divorced', 'Widowed', 'Awaiting Divorce', 'Annulled'];
const _dietOptions = ['Veg', 'Non-Veg', 'Occasionally Non-Veg', 'Eggetarian', 'Jain', 'Vegan'];

List<({String label, int cm})> _heightOptions() {
  return List.generate(213 - 134 + 1, (i) {
    final cm = 134 + i;
    final totalInches = (cm / 2.54).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return (label: "${feet}ft ${inches}in - ${cm}cm", cm: cm);
  });
}

MaritalStatus? _parseMaritalStatus(String label) => switch (label) {
      'Never Married' => MaritalStatus.neverMarried,
      'Divorced' => MaritalStatus.divorced,
      'Widowed' => MaritalStatus.widowed,
      'Awaiting Divorce' => MaritalStatus.awaitingDivorce,
      _ => MaritalStatus.neverMarried,
    };

DietType? _parseDiet(String label) => switch (label) {
      'Veg' => DietType.vegetarian,
      'Non-Veg' => DietType.nonVegetarian,
      'Occasionally Non-Veg' => DietType.nonVegetarian,
      'Eggetarian' => DietType.eggetarian,
      'Jain' => DietType.jain,
      'Vegan' => DietType.vegan,
      _ => null,
    };

/// Marital status, height, and diet — one compact screen, no section
/// headers in the reference, just the three fields stacked.
class MaritalHeightDietScreen extends ConsumerWidget {
  const MaritalHeightDietScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final heightOptions = _heightOptions();
    final currentHeightLabel =
        heightOptions.where((h) => h.cm == draft.heightCm).map((h) => h.label).firstOrNull;

    final canContinue = draft.maritalStatus != null && draft.heightCm != null;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 4,
      stepCount: onboardingStepCount,
      title: '',
      headerIcon: Icons.badge_rounded,
      onContinue: canContinue ? () => context.push(AppRoutes.qualification) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Marital status', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: '${profileFor.possessiveTitle} Marital status *',
            value: draft.maritalStatus?.label,
            options: _maritalOptions,
            onSelected: (v) =>
                controller.update((p) => p.copyWith(maritalStatus: _parseMaritalStatus(v))),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Height', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: '${profileFor.possessiveTitle} Height *',
            value: currentHeightLabel,
            options: heightOptions.map((h) => h.label).toList(),
            onSelected: (v) {
              final match = heightOptions.where((h) => h.label == v).firstOrNull;
              if (match != null) controller.update((p) => p.copyWith(heightCm: match.cm));
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Diet', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: '${profileFor.possessiveTitle} Diet',
            value: draft.diet == null ? null : _dietOptions.firstWhere(
                (d) => _parseDiet(d) == draft.diet, orElse: () => _dietOptions.first),
            options: _dietOptions,
            onSelected: (v) => controller.update((p) => p.copyWith(diet: _parseDiet(v))),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
