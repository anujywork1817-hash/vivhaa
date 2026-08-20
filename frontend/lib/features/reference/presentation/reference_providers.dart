import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reference_models.dart';
import '../data/reference_repository.dart';

/// Riverpod wrappers over [ReferenceRepository].
///
/// Each throws on failure so screens can lean on `AsyncValue.when` and get
/// loading and error states for free, rather than every picker hand-rolling
/// its own. The repository memoises the underlying responses, so a provider
/// rebuild is cheap.

final countriesProvider = FutureProvider<List<RefCountry>>((ref) async {
  final result = await ref.watch(referenceRepositoryProvider).countries();
  return result.when(
    success: (data) => data,
    failure: (f) => throw f,
  );
});

/// States for one ISO country code. Keyed by country because a state code is
/// only unique within its country.
final statesProvider =
    FutureProvider.family<List<RefState>, String>((ref, countryCode) async {
  final result = await ref.watch(referenceRepositoryProvider).states(countryCode);
  return result.when(
    success: (data) => data,
    failure: (f) => throw f,
  );
});

/// Identifies one state anywhere in the world, plus an optional search term.
///
/// Records give this value equality for free, which is what lets Riverpod
/// dedupe the family: two widgets asking for `(US, TX)` share one request.
typedef CityQuery = ({String countryCode, String stateCode, String query});

final citiesProvider =
    FutureProvider.family<List<String>, CityQuery>((ref, q) async {
  final result = await ref.watch(referenceRepositoryProvider).cities(
        q.countryCode,
        q.stateCode,
        query: q.query,
      );
  return result.when(
    success: (data) => data,
    failure: (f) => throw f,
  );
});

final religionsProvider = FutureProvider<List<RefReligion>>((ref) async {
  final result = await ref.watch(referenceRepositoryProvider).religions();
  return result.when(
    success: (data) => data,
    failure: (f) => throw f,
  );
});

/// Communities under the chosen religion, or empty when nothing is chosen
/// yet. Reads the already-fetched tree, so this costs no extra request.
final communitiesProvider =
    Provider.family<List<RefCommunity>, String?>((ref, religion) {
  if (religion == null) return const [];
  final religions = ref.watch(religionsProvider).valueOrNull;
  if (religions == null) return const [];
  for (final r in religions) {
    if (r.name == religion) return r.communities;
  }
  return const [];
});

/// Sub-castes under a religion/community pair.
typedef CommunityKey = ({String? religion, String? community});

final subCastesProvider =
    Provider.family<List<String>, CommunityKey>((ref, key) {
  for (final c in ref.watch(communitiesProvider(key.religion))) {
    if (c.name == key.community) return c.subCastes;
  }
  return const [];
});
