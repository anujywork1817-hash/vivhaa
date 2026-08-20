import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_favourite_repository.dart';
import '../../domain/favourite_repository.dart';

/// The current user's favourited profiles, for the Favourites list screen.
final favouritesListProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(favouriteRepositoryProvider).getFavourites();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

/// Tracks which profile IDs are favourited, for toggle buttons elsewhere
/// (e.g. the profile-detail actions sheet) that need a fast yes/no without
/// re-fetching the whole list — mirrors [InterestActionsController]'s
/// shortlist pattern.
class FavouriteActionsState {
  final Set<String> favourited;

  const FavouriteActionsState({this.favourited = const {}});

  FavouriteActionsState copyWith({Set<String>? favourited}) {
    return FavouriteActionsState(favourited: favourited ?? this.favourited);
  }
}

class FavouriteActionsController extends StateNotifier<FavouriteActionsState> {
  final FavouriteRepository _repository;
  final Ref _ref;

  FavouriteActionsController(this._repository, this._ref) : super(const FavouriteActionsState()) {
    _load();
  }

  Future<void> _load() async {
    final result = await _repository.getFavourites();
    result.when(
      success: (profiles) =>
          state = state.copyWith(favourited: profiles.map((p) => p.id).toSet()),
      failure: (_) {},
    );
  }

  Future<void> toggleFavourite(String profileId) async {
    final wasFavourited = state.favourited.contains(profileId);
    final optimistic = {...state.favourited};
    wasFavourited ? optimistic.remove(profileId) : optimistic.add(profileId);
    state = state.copyWith(favourited: optimistic);

    final result =
        wasFavourited ? await _repository.remove(profileId) : await _repository.add(profileId);
    result.when(
      success: (_) => _ref.invalidate(favouritesListProvider),
      failure: (_) {
        final reverted = {...state.favourited};
        wasFavourited ? reverted.add(profileId) : reverted.remove(profileId);
        state = state.copyWith(favourited: reverted);
      },
    );
  }

  bool isFavourited(String profileId) => state.favourited.contains(profileId);
}

final favouriteActionsProvider =
    StateNotifierProvider<FavouriteActionsController, FavouriteActionsState>((ref) {
  return FavouriteActionsController(ref.watch(favouriteRepositoryProvider), ref);
});
