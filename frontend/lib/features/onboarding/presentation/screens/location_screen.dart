import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/inputs/app_searchable_select_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../../../reference/data/reference_models.dart';
import '../../../reference/data/reference_repository.dart';
import '../../../reference/presentation/reference_providers.dart';
import '../controllers/profile_creation_controller.dart';

/// "Now let's build your Profile" — state, city, and sub-caste.
///
/// Every list here cascades off an earlier answer: states off the country
/// picked on the previous step, cities off that state, sub-castes off the
/// community. Previously all three were fixed constants, so a member living
/// in Texas was offered Maharashtra's twelve states and five of its cities.
class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    // The draft stores country/state by name because that is what the API
    // persists, but the lookups are keyed by ISO code — so resolve the codes
    // back out of the lists that produced those names.
    final countriesAsync = ref.watch(countriesProvider);
    final countryCode = _codeForCountry(countriesAsync.valueOrNull, draft.country);

    final statesAsync = countryCode == null
        ? const AsyncValue<List<RefState>>.data([])
        : ref.watch(statesProvider(countryCode));
    final stateCode = _codeForState(statesAsync.valueOrNull, draft.state);

    final citiesAsync = (countryCode == null || stateCode == null)
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(citiesProvider(
            (countryCode: countryCode, stateCode: stateCode, query: '')));

    final subCastes = ref.watch(
      subCastesProvider((religion: draft.religion, community: draft.community)),
    );

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
          AppSearchableSelectField(
            label: 'State',
            hint: 'State you live in',
            value: draft.state,
            enabled: countryCode != null,
            emptyMessage: countryCode == null
                ? 'Go back and choose a country first'
                : '${draft.country} has no states to choose from',
            options: [
              for (final s in statesAsync.valueOrNull ?? const <RefState>[])
                SelectOption(s.name),
            ],
            isLoading: statesAsync.isLoading,
            errorMessage: statesAsync.hasError ? _listError : null,
            onRetry: countryCode == null
                ? null
                : () => ref.invalidate(statesProvider(countryCode)),
            onSelected: (o) =>
                controller.update((p) => p.copyWith(state: o.value, clearCity: true)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('City', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSearchableSelectField(
            label: 'City',
            hint: 'City you live in',
            value: draft.city,
            enabled: stateCode != null,
            emptyMessage: 'Choose a state first',
            options: [
              for (final c in citiesAsync.valueOrNull ?? const <String>[])
                SelectOption(c),
            ],
            isLoading: citiesAsync.isLoading,
            errorMessage: citiesAsync.hasError ? _listError : null,
            // A large state's list is capped by the API, so searching goes
            // back to the server rather than filtering the truncated page.
            onSearch: (countryCode == null || stateCode == null)
                ? null
                : (query) async {
                    final result = await ref
                        .read(referenceRepositoryProvider)
                        .cities(countryCode, stateCode, query: query);
                    return result.when(
                      success: (cities) =>
                          cities.map((c) => SelectOption(c)).toList(growable: false),
                      failure: (_) => const <SelectOption>[],
                    );
                  },
            onSelected: (o) => controller.update((p) => p.copyWith(city: o.value)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Sub-caste', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSearchableSelectField(
            label: 'Sub-caste',
            hint: 'Your sub-caste',
            value: draft.subCommunity,
            enabled: draft.community != null,
            emptyMessage: draft.community == null
                ? 'Go back and choose a community first'
                : 'No sub-castes listed for ${draft.community}',
            options: [for (final s in subCastes) SelectOption(s)],
            onSelected: (o) => controller.update((p) => p.copyWith(subCommunity: o.value)),
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

/// The draft persists a country by name, so the ISO code the state and city
/// endpoints need has to be resolved back from the loaded list. Returns null
/// while the list is still in flight, which is what leaves the state picker
/// disabled rather than briefly showing it empty.
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

const _listError = "Couldn't load this list. Check your connection and try again.";
