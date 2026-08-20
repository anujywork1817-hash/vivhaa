import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/search_filters.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/choice_chip_group.dart';
import '../controllers/search_filters_controller.dart';
import '../controllers/search_results_controller.dart';

const _maritalOptions = ['Never Married', 'Divorced', 'Widowed'];
const _religionOptions = ['Hindu', 'Muslim', 'Christian', 'Sikh', 'Jain'];

/// Quick re-sort / re-filter on top of results already on screen —
/// applies immediately and re-runs the search, distinct from the full
/// Basic/Advanced Search forms.
class SortFilterSheet extends ConsumerWidget {
  const SortFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchFiltersProvider.notifier);
    final filters = ref.watch(searchFiltersProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.colors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Sort & Filter', style: context.textStyles.headlineSmall),
            const SizedBox(height: AppSpacing.lg),
            Text('Sort by', style: context.textStyles.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: SortOption.values.map((option) {
                final isSelected = filters.sort == option;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (_) => controller.update((f) => f.copyWith(sort: option)),
                  labelStyle: TextStyle(
                    color: isSelected ? context.colors.accent : context.colors.ink,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  side: BorderSide(color: isSelected ? context.colors.accent : context.colors.line),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            ChoiceChipGroup<String>(
              label: 'Marital status',
              options: _maritalOptions,
              labelBuilder: (v) => v,
              selected: filters.maritalStatuses,
              onToggle: (v) => controller.update((f) {
                final updated = {...f.maritalStatuses};
                updated.contains(v) ? updated.remove(v) : updated.add(v);
                return f.copyWith(maritalStatuses: updated);
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            ChoiceChipGroup<String>(
              label: 'Religion',
              options: _religionOptions,
              labelBuilder: (v) => v,
              selected: filters.religions,
              onToggle: (v) => controller.update((f) {
                final updated = {...f.religions};
                updated.contains(v) ? updated.remove(v) : updated.add(v);
                return f.copyWith(religions: updated);
              }),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => controller.reset(),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: 'Apply',
                    onPressed: () async {
                      await ref.read(searchResultsControllerProvider.notifier).runSearch(filters);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
