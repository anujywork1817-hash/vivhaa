import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_demo_repository.dart';

class DemoSwipeState {
  final List<MatchProfile> queue;
  final int index;
  final bool loading;

  const DemoSwipeState({this.queue = const [], this.index = 0, this.loading = true});

  MatchProfile? get current => index < queue.length ? queue[index] : null;
  MatchProfile? get next => index + 1 < queue.length ? queue[index + 1] : null;
  bool get isExhausted => !loading && index >= queue.length;

  DemoSwipeState copyWith({List<MatchProfile>? queue, int? index, bool? loading}) {
    return DemoSwipeState(
      queue: queue ?? this.queue,
      index: index ?? this.index,
      loading: loading ?? this.loading,
    );
  }
}

/// Drives the free "hook" swipe deck of the fixed 10 male + 10 female demo
/// profiles every user sees right after onboarding (see internal/demo on
/// the backend). Swipes are tracked purely client-side (index into the
/// queue) — there's no per-swipe endpoint to call, since a demo profile
/// has no real other side to receive an interest.
class DemoSwipeController extends StateNotifier<DemoSwipeState> {
  final ApiDemoRepository _repository;

  DemoSwipeController(this._repository) : super(const DemoSwipeState()) {
    _load();
  }

  Future<void> _load() async {
    state = state.copyWith(loading: true);
    final result = await _repository.getSwipeDeck();
    result.when(
      success: (profiles) => state = DemoSwipeState(queue: profiles, index: 0, loading: false),
      failure: (_) => state = const DemoSwipeState(loading: false),
    );
  }

  void advance() {
    if (state.index < state.queue.length) {
      state = state.copyWith(index: state.index + 1);
    }
  }
}

final demoSwipeControllerProvider =
    StateNotifierProvider.autoDispose<DemoSwipeController, DemoSwipeState>((ref) {
  return DemoSwipeController(ref.watch(demoRepositoryProvider));
});
