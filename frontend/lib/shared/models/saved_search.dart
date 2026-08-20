import 'search_filters.dart';

class SavedSearch {
  final String id;
  final String name;
  final SearchFilters filters;
  final DateTime createdAt;
  final int resultCount;

  const SavedSearch({
    required this.id,
    required this.name,
    required this.filters,
    required this.createdAt,
    required this.resultCount,
  });
}
