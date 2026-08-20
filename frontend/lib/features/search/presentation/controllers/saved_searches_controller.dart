import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/saved_search.dart';
import '../../../../shared/models/search_filters.dart';
import '../../data/api_search_repository.dart';

final savedSearchesProvider =
    FutureProvider.autoDispose<List<SavedSearch>>((ref) async {
  final result = await ref.watch(searchRepositoryProvider).getSavedSearches();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

class SavedSearchActions {
  final Ref ref;
  SavedSearchActions(this.ref);

  Future<void> save(String name, SearchFilters filters, int resultCount) async {
    await ref.read(searchRepositoryProvider).saveSearch(name, filters, resultCount);
    ref.invalidate(savedSearchesProvider);
  }

  Future<void> delete(String id) async {
    await ref.read(searchRepositoryProvider).deleteSavedSearch(id);
    ref.invalidate(savedSearchesProvider);
  }
}

final savedSearchActionsProvider = Provider((ref) => SavedSearchActions(ref));
