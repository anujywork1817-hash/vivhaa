import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_select_field.dart';
import '../controllers/profile_creation_controller.dart';

const _occupations = [
  'Homemaker', 'Private Job', 'Government Job', 'Business / Self Employed',
  'Retired', 'Not Working', 'Farmer',
];
const _siblingCounts = ['0', '1', '2', '3', '4', '5+'];
const _financialStatuses = ['Elite', 'High', 'Middle', 'Aspiring'];

/// "Add family details" — mother's/father's occupation, siblings, and
/// (further down the same screen) whether the member lives with family
/// and the family's financial status.
class FamilyDetailsScreen extends ConsumerWidget {
  const FamilyDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    final canContinue = draft.motherOccupation != null &&
        draft.fatherOccupation != null &&
        draft.livesWithFamily != null &&
        draft.familyFinancialStatus != null;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => context.push(AppRoutes.partnerPreferences),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration:
                          BoxDecoration(color: context.colors.accentSoft, shape: BoxShape.circle),
                      child: Icon(Icons.diversity_1_rounded, color: context.colors.accent, size: 30),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Add ${profileFor.possessive} family details',
                      style: context.textStyles.headlineMedium),
                  const SizedBox(height: 4),
                  Text('This really helps find common connections',
                      style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
                  const SizedBox(height: AppSpacing.xl),
                  AppSelectField(
                    label: "Mother's details",
                    value: draft.motherOccupation,
                    options: _occupations,
                    onSelected: (v) => controller.update((p) => p.copyWith(motherOccupation: v)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppSelectField(
                    label: "Father's details",
                    value: draft.fatherOccupation,
                    options: _occupations,
                    onSelected: (v) => controller.update((p) => p.copyWith(fatherOccupation: v)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppSelectField(
                    label: 'No. of Sisters',
                    value: draft.sisters?.toString(),
                    options: _siblingCounts,
                    onSelected: (v) => controller
                        .update((p) => p.copyWith(sisters: int.tryParse(v.replaceAll('+', '')))),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppSelectField(
                    label: 'No. of Brothers',
                    value: draft.brothers?.toString(),
                    options: _siblingCounts,
                    onSelected: (v) => controller
                        .update((p) => p.copyWith(brothers: int.tryParse(v.replaceAll('+', '')))),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text('${profileFor.possessiveTitle} Family Location',
                      style: context.textStyles.titleMedium),
                  const SizedBox(height: 4),
                  Text('Living with family?', style: context.textStyles.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      _ToggleChip(
                        label: 'Yes',
                        selected: draft.livesWithFamily == true,
                        onTap: () => controller.update((p) => p.copyWith(livesWithFamily: true)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _ToggleChip(
                        label: 'No',
                        selected: draft.livesWithFamily == false,
                        onTap: () => controller.update((p) => p.copyWith(livesWithFamily: false)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text("${profileFor.possessiveTitle} Family's Financial Status",
                      style: context.textStyles.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  RadioGroup<String>(
                    groupValue: draft.familyFinancialStatus,
                    onChanged: (v) =>
                        controller.update((p) => p.copyWith(familyFinancialStatus: v)),
                    child: Column(
                      children: _financialStatuses
                          .map((status) => RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                title: Text(status),
                                value: status,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: PrimaryButton(
              label: 'Continue',
              onPressed: canContinue ? () => context.push(AppRoutes.partnerPreferences) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: context.colors.accentSoft,
      labelStyle: TextStyle(color: selected ? context.colors.accent : context.colors.ink),
      side: BorderSide(color: selected ? context.colors.accent : context.colors.line),
    );
  }
}
