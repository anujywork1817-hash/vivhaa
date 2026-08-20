import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/search_filters.dart';

/// Draft filters being edited across Basic Search, Advanced Search, and
/// the Sort & Filter sheet — one shared draft so filling in Basic Search
/// and then opening Advanced Search doesn't lose what was already set.
class SearchFiltersController extends StateNotifier<SearchFilters> {
  SearchFiltersController() : super(const SearchFilters());

  void update(SearchFilters Function(SearchFilters current) updater) {
    state = updater(state);
  }

  void reset() => state = state.reset();
}

final searchFiltersProvider =
    StateNotifierProvider<SearchFiltersController, SearchFilters>((ref) {
  return SearchFiltersController();
});
