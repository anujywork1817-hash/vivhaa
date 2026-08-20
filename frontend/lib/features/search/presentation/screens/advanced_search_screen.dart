import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_select_field.dart';
import '../../../../shared/widgets/inputs/choice_chip_group.dart';
import '../controllers/search_filters_controller.dart';
import '../controllers/search_results_controller.dart';

const _communities = [
  'Brahmin', 'Rajput', 'Kayastha', 'Yadav', 'Reddy', 'Nair', 'Iyer', 'Sunni', 'Jat', 'Maratha',
];
const _education = ["Bachelor's Degree", "Master's Degree", 'MBA', 'Doctorate (PhD)'];
const _professions = [
  'Software Engineer', 'Doctor', 'Chartered Accountant', 'Architect', 'Teacher',
  'Marketing Manager', 'Civil Servant', 'Lawyer', 'Entrepreneur', 'Banker',
];
const _incomeOptions = [
  'Below ₹3 Lakh', '₹3–6 Lakh', '₹6–10 Lakh', '₹10–15 Lakh', '₹15–25 Lakh', '₹25 Lakh+',
];
const _dietOptions = ['Vegetarian', 'Non-Vegetarian', 'Eggetarian', 'Vegan', 'Jain'];
const _manglikOptions = ['Yes', 'No', "Don't know"];

/// Refines whatever's already set on Basic Search — same shared
/// [searchFiltersProvider] draft, so this screen only adds fields rather
/// than starting the search over.
class AdvancedSearchScreen extends ConsumerWidget {
  const AdvancedSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchFiltersProvider.notifier);
    final filters = ref.watch(searchFiltersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Search')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChoiceChipGroup<String>(
                      label: 'Community',
                      options: _communities,
                      labelBuilder: (v) => v,
                      selected: filters.communities,
                      onToggle: (v) => controller.update((f) {
                        final updated = {...f.communities};
                        updated.contains(v) ? updated.remove(v) : updated.add(v);
                        return f.copyWith(communities: updated);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ChoiceChipGroup<String>(
                      label: 'Education',
                      options: _education,
                      labelBuilder: (v) => v,
                      selected: filters.education,
                      onToggle: (v) => controller.update((f) {
                        final updated = {...f.education};
                        updated.contains(v) ? updated.remove(v) : updated.add(v);
                        return f.copyWith(education: updated);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ChoiceChipGroup<String>(
                      label: 'Profession',
                      options: _professions,
                      labelBuilder: (v) => v,
                      selected: filters.professions,
                      onToggle: (v) => controller.update((f) {
                        final updated = {...f.professions};
                        updated.contains(v) ? updated.remove(v) : updated.add(v);
                        return f.copyWith(professions: updated);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppSelectField(
                      label: 'Minimum annual income',
                      value: filters.incomeMin,
                      options: _incomeOptions,
                      onSelected: (v) => controller.update((f) => f.copyWith(incomeMin: v)),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ChoiceChipGroup<String>(
                      label: 'Diet',
                      options: _dietOptions,
                      labelBuilder: (v) => v,
                      selected: filters.diet == null ? {} : {filters.diet!},
                      onToggle: (v) => controller.update(
                          (f) => f.copyWith(diet: f.diet == v ? null : v, clearDiet: f.diet == v)),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ChoiceChipGroup<String>(
                      label: 'Manglik',
                      options: _manglikOptions,
                      labelBuilder: (v) => v,
                      selected: filters.manglik == null ? {} : {filters.manglik!},
                      onToggle: (v) => controller.update((f) => f.copyWith(
                          manglik: f.manglik == v ? null : v, clearManglik: f.manglik == v)),
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
