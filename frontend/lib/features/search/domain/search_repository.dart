import '../../../core/api/api_result.dart';
import '../../../shared/models/match_profile.dart';
import '../../../shared/models/saved_search.dart';
import '../../../shared/models/search_filters.dart';

abstract class SearchRepository {
  Future<ApiResult<List<MatchProfile>>> search(SearchFilters filters, {int page = 0});
  Future<ApiResult<MatchProfile?>> findByProfileId(String profileId);
  Future<ApiResult<List<SavedSearch>>> getSavedSearches();
  Future<ApiResult<SavedSearch>> saveSearch(String name, SearchFilters filters, int resultCount);
  Future<ApiResult<void>> deleteSavedSearch(String id);
}
