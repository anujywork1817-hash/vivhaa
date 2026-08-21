import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/call_history_entry.dart';
import '../../data/api_call_repository.dart';
import '../../domain/call_repository.dart';

const int _pageSize = ApiCallRepository.historyPageSize;

class CallHistoryState {
  final List<CallHistoryEntry> entries;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final AppFailure? failure;

  const CallHistoryState({
    this.entries = const [],
    this.page = 0,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.failure,
  });

  CallHistoryState copyWith({
    List<CallHistoryEntry>? entries,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    AppFailure? failure,
    bool clearFailure = false,
  }) {
    return CallHistoryState(
      entries: entries ?? this.entries,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}

/// Paginated call history (page/limit), same load-more shape as
/// SearchResultsController — the app has no other paginated-list
/// controller to follow, so this mirrors that one.
class CallHistoryController extends StateNotifier<CallHistoryState> {
  final CallRepository _repository;

  CallHistoryController(this._repository) : super(const CallHistoryState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearFailure: true, page: 0);
    final result = await _repository.getCallHistory(page: 0);
    result.when(
      success: (data) {
        state = state.copyWith(
          loading: false,
          entries: data,
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
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    final nextPage = state.page + 1;
    final result = await _repository.getCallHistory(page: nextPage);
    result.when(
      success: (data) {
        state = state.copyWith(
          loadingMore: false,
          entries: [...state.entries, ...data],
          page: nextPage,
          hasMore: data.length >= _pageSize,
        );
      },
      failure: (f) {
        state = state.copyWith(loadingMore: false, failure: f);
      },
    );
  }
}

final callHistoryControllerProvider =
    StateNotifierProvider.autoDispose<CallHistoryController, CallHistoryState>((ref) {
  return CallHistoryController(ref.watch(callRepositoryProvider));
});
