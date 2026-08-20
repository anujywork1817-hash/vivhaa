import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/api_shortlist_repository.dart';
import '../../domain/shortlist_repository.dart';

/// Tracks which profile IDs the current user has shortlisted, backed by
/// the real `/shortlisted/*` endpoints. Expressing interest is handled
/// separately by [InterestsActions] since — unlike a shortlist — it has
/// to go through a real accept/decline lifecycle.
class InterestActionsState {
  final Set<String> shortlisted;

  const InterestActionsState({this.shortlisted = const {}});

  InterestActionsState copyWith({Set<String>? shortlisted}) {
    return InterestActionsState(shortlisted: shortlisted ?? this.shortlisted);
  }
}

class InterestActionsController extends StateNotifier<InterestActionsState> {
  final ShortlistRepository _repository;

  InterestActionsController(this._repository) : super(const InterestActionsState()) {
    _load();
  }

  Future<void> _load() async {
    final result = await _repository.getShortlistedProfileIds();
    result.when(
      success: (ids) => state = state.copyWith(shortlisted: ids.toSet()),
      failure: (_) {},
    );
  }

  /// Optimistically flips local state, then reconciles with the backend —
  /// reverting if the call fails, so a dropped connection can't leave the
  /// UI showing a shortlist state that was never actually saved.
  Future<void> toggleShortlist(String profileId) async {
    final wasShortlisted = state.shortlisted.contains(profileId);
    final optimistic = {...state.shortlisted};
    wasShortlisted ? optimistic.remove(profileId) : optimistic.add(profileId);
    state = state.copyWith(shortlisted: optimistic);

    final result =
        wasShortlisted ? await _repository.remove(profileId) : await _repository.add(profileId);
    result.when(
      success: (_) {},
      failure: (_) {
        final reverted = {...state.shortlisted};
        wasShortlisted ? reverted.add(profileId) : reverted.remove(profileId);
        state = state.copyWith(shortlisted: reverted);
      },
    );
  }

  bool isShortlisted(String profileId) => state.shortlisted.contains(profileId);
}

final interestActionsProvider =
    StateNotifierProvider<InterestActionsController, InterestActionsState>((ref) {
  return InterestActionsController(ref.watch(shortlistRepositoryProvider));
});
