import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_select_field.dart';
import '../../../../shared/widgets/inputs/choice_chip_group.dart';
import '../controllers/search_filters_controller.dart';
import '../controllers/search_results_controller.dart';

const _maritalOptions = ['Never Married', 'Divorced', 'Widowed'];
const _religionOptions = ['Hindu', 'Muslim', 'Christian', 'Sikh', 'Jain'];
const _cities = [
  'Mumbai', 'Bengaluru', 'Delhi', 'Pune', 'Hyderabad', 'Chennai', 'Ahmedabad', 'Kolkata',
  'Jaipur', 'Surat',
];

class BasicSearchScreen extends ConsumerWidget {
  const BasicSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchFiltersProvider.notifier);
    final filters = ref.watch(searchFiltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Basic Search'),
        actions: [
          TextButton(
            onPressed: () => controller.reset(),
            child: const Text('Reset'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Age: ${filters.ageMin}–${filters.ageMax} yrs',
                        style: context.textStyles.titleSmall),
                    RangeSlider(
                      values: RangeValues(filters.ageMin.toDouble(), filters.ageMax.toDouble()),
                      min: 18,
                      max: 65,
                      divisions: 47,
                      onChanged: (v) => controller.update(
                          (f) => f.copyWith(ageMin: v.start.round(), ageMax: v.end.round())),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                        'Height: ${filters.heightMinCm}–${filters.heightMaxCm} cm',
                        style: context.textStyles.titleSmall),
                    RangeSlider(
                      values: RangeValues(
                          filters.heightMinCm.toDouble(), filters.heightMaxCm.toDouble()),
                      min: 122,
                      max: 213,
                      divisions: 91,
                      onChanged: (v) => controller.update((f) => f.copyWith(
                          heightMinCm: v.start.round(), heightMaxCm: v.end.round())),
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                    const SizedBox(height: AppSpacing.lg),
                    AppSelectField(
                      label: 'City',
                      value: filters.city,
                      options: _cities,
                      onSelected: (v) => controller.update((f) => f.copyWith(city: v)),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => context.push(AppRoutes.advancedSearch),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Advanced Search'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: PrimaryButton(
                label: 'Search',
                onPressed: () async {
                  await ref.read(searchResultsControllerProvider.notifier).runSearch(filters);
                  if (context.mounted) context.push(AppRoutes.searchResults);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
