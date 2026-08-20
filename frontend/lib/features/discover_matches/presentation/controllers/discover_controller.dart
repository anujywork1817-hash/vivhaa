import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../dashboard/data/api_dashboard_repository.dart';
import '../../../dashboard/domain/dashboard_repository.dart';

class DiscoverState {
  final List<MatchProfile> queue;
  final int index;
  final bool loading;

  const DiscoverState({this.queue = const [], this.index = 0, this.loading = true});

  MatchProfile? get current => index < queue.length ? queue[index] : null;
  MatchProfile? get next => index + 1 < queue.length ? queue[index + 1] : null;
  bool get isExhausted => !loading && index >= queue.length;

  DiscoverState copyWith({List<MatchProfile>? queue, int? index, bool? loading}) {
    return DiscoverState(
      queue: queue ?? this.queue,
      index: index ?? this.index,
      loading: loading ?? this.loading,
    );
  }
}

/// Swipe-deck queue for the Discover screen, sourced from the same
/// recommended-matches pool as the dashboard's "Recommended for you" —
/// there's no separate "browse" endpoint on the backend, so this is the
/// best available candidate pool for a swipe deck.
class DiscoverController extends StateNotifier<DiscoverState> {
  final DashboardRepository _repository;

  DiscoverController(this._repository) : super(const DiscoverState()) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(loading: true);
    final result = await _repository.getRecommendedMatches();
    result.when(
      success: (profiles) => state = DiscoverState(queue: profiles, index: 0, loading: false),
      failure: (_) => state = const DiscoverState(loading: false),
    );
  }

  void advance() {
    if (state.index < state.queue.length) {
      state = state.copyWith(index: state.index + 1);
    }
  }

  void reset() => _load();
}

final discoverControllerProvider =
    StateNotifierProvider.autoDispose<DiscoverController, DiscoverState>((ref) {
  return DiscoverController(ref.watch(dashboardRepositoryProvider));
});
