import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/models/search_filters.dart';
import '../../data/api_search_repository.dart';
import '../../domain/search_repository.dart';

const int _pageSize = ApiSearchRepository.pageSize;

class SearchResultsState {
  final List<MatchProfile> results;
  final SearchFilters? appliedFilters;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final AppFailure? failure;
  final bool hasSearched;

  const SearchResultsState({
    this.results = const [],
    this.appliedFilters,
    this.page = 0,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.failure,
    this.hasSearched = false,
  });

  SearchResultsState copyWith({
    List<MatchProfile>? results,
    SearchFilters? appliedFilters,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    AppFailure? failure,
    bool clearFailure = false,
    bool? hasSearched,
  }) {
    return SearchResultsState(
      results: results ?? this.results,
      appliedFilters: appliedFilters ?? this.appliedFilters,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      failure: clearFailure ? null : failure ?? this.failure,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

class SearchResultsController extends StateNotifier<SearchResultsState> {
  final SearchRepository _repository;

  SearchResultsController(this._repository) : super(const SearchResultsState());

  Future<void> runSearch(SearchFilters filters) async {
    state = state.copyWith(
      loading: true,
      clearFailure: true,
      appliedFilters: filters,
      page: 0,
      hasSearched: true,
    );
    final result = await _repository.search(filters, page: 0);
    result.when(
      success: (data) {
        state = state.copyWith(
          loading: false,
          results: data,
          page: 0,
          hasMore: data.length >= _pageSize,
        );
      },
      failure: (f) {
        state = state.copyWith(loading: false, failure: f);
      },
    );
  }

  Future<void> loadMore() async {
    final filters = state.appliedFilters;
    if (filters == null || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    final nextPage = state.page + 1;
    final result = await _repository.search(filters, page: nextPage);
    result.when(
      success: (data) {
        state = state.copyWith(
          loadingMore: false,
          results: [...state.results, ...data],
          page: nextPage,
          hasMore: data.length >= _pageSize,
        );
      },
      failure: (f) {
        state = state.copyWith(loadingMore: false, failure: f);
      },
    );
  }

  Future<void> retry() async {
    final filters = state.appliedFilters;
    if (filters != null) await runSearch(filters);
  }
}

final searchResultsControllerProvider =
    StateNotifierProvider<SearchResultsController, SearchResultsState>((ref) {
  return SearchResultsController(ref.watch(searchRepositoryProvider));
});
