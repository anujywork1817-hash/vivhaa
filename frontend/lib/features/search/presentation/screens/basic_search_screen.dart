import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_searchable_select_field.dart';
import '../../../reference/data/reference_models.dart';
import '../../../reference/data/reference_repository.dart';
import '../../../reference/presentation/reference_providers.dart';
import '../../../../shared/widgets/inputs/choice_chip_group.dart';
import '../controllers/search_filters_controller.dart';
import '../controllers/search_results_controller.dart';

const _maritalOptions = ['Never Married', 'Divorced', 'Widowed'];

class BasicSearchScreen extends ConsumerWidget {
  const BasicSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchFiltersProvider.notifier);
    final filters = ref.watch(searchFiltersProvider);

    final religionNames = <String>[
      for (final r in ref.watch(religionsProvider).valueOrNull ?? const <RefReligion>[])
        r.name,
    ];

    // Country only narrows the pickers below it; the search request drops it
    // because the index has no country field to filter on.
    final countryCode =
        _codeForCountry(ref.watch(countriesProvider).valueOrNull, filters.country);
    final statesAsync = countryCode == null
        ? const AsyncValue<List<RefState>>.data([])
        : ref.watch(statesProvider(countryCode));
    final stateCode = _codeForState(statesAsync.valueOrNull, filters.state);
    final citiesAsync = (countryCode == null || stateCode == null)
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(citiesProvider(
            (countryCode: countryCode, stateCode: stateCode, query: '')));

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
                      options: religionNames,
                      labelBuilder: (v) => v,
                      selected: filters.religions,
                      onToggle: (v) => controller.update((f) {
                        final updated = {...f.religions};
                        updated.contains(v) ? updated.remove(v) : updated.add(v);
                        return f.copyWith(religions: updated);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppSearchableSelectField(
                      label: 'Country',
                      hint: 'Any country',
                      value: filters.country,
                      options: [
                        for (final c in ref.watch(countriesProvider).valueOrNull ??
                            const <RefCountry>[])
                          SelectOption(c.name, c.label),
                      ],
                      isLoading: ref.watch(countriesProvider).isLoading,
                      onSelected: (o) => controller.update((f) =>
                          f.copyWith(country: o.value, clearState: true, clearCity: true)),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppSearchableSelectField(
                      label: 'State',
                      hint: 'Any state',
                      value: filters.state,
                      enabled: countryCode != null,
                      emptyMessage: 'Choose a country first',
                      options: [
                        for (final s in statesAsync.valueOrNull ?? const <RefState>[])
                          SelectOption(s.name),
                      ],
                      isLoading: statesAsync.isLoading,
                      onSelected: (o) => controller
                          .update((f) => f.copyWith(state: o.value, clearCity: true)),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppSearchableSelectField(
                      label: 'City',
                      hint: 'Any city',
                      value: filters.city,
                      enabled: stateCode != null,
                      emptyMessage: 'Choose a state first',
                      options: [
                        for (final c in citiesAsync.valueOrNull ?? const <String>[])
                          SelectOption(c),
                      ],
                      isLoading: citiesAsync.isLoading,
                      onSearch: (countryCode == null || stateCode == null)
                          ? null
                          : (query) async {
                              final result = await ref
                                  .read(referenceRepositoryProvider)
                                  .cities(countryCode, stateCode, query: query);
                              return result.when(
                                success: (cities) => cities
                                    .map((c) => SelectOption(c))
                                    .toList(growable: false),
                                failure: (_) => const <SelectOption>[],
                              );
                            },
                      onSelected: (o) =>
                          controller.update((f) => f.copyWith(city: o.value)),
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

String? _codeForCountry(List<RefCountry>? countries, String? name) {
  if (countries == null || name == null) return null;
  for (final c in countries) {
    if (c.name == name) return c.code;
  }
  return null;
}

String? _codeForState(List<RefState>? states, String? name) {
  if (states == null || name == null) return null;
  for (final s in states) {
    if (s.name == name) return s.code;
  }
  return null;
}
