import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_search_repository.dart';
import '../../domain/search_repository.dart';

class ProfileIdSearchState {
  final bool loading;
  final bool searched;
  final MatchProfile? result;
  final AppFailure? failure;

  const ProfileIdSearchState({
    this.loading = false,
    this.searched = false,
    this.result,
    this.failure,
  });
}

class ProfileIdSearchController extends StateNotifier<ProfileIdSearchState> {
  final SearchRepository _repository;
  ProfileIdSearchController(this._repository) : super(const ProfileIdSearchState());

  Future<void> search(String profileId) async {
    if (profileId.trim().isEmpty) return;
    state = const ProfileIdSearchState(loading: true, searched: true);
    final result = await _repository.findByProfileId(profileId);
    result.when(
      success: (profile) => state = ProfileIdSearchState(searched: true, result: profile),
      failure: (f) => state = ProfileIdSearchState(searched: true, failure: f),
    );
  }
}

final profileIdSearchControllerProvider =
    StateNotifierProvider.autoDispose<ProfileIdSearchController, ProfileIdSearchState>((ref) {
  return ProfileIdSearchController(ref.watch(searchRepositoryProvider));
});
