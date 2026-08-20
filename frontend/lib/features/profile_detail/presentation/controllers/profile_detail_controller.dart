import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/models/profile_detail.dart';
import '../../data/api_profile_detail_repository.dart';

final profileDetailProvider =
    FutureProvider.autoDispose.family<ProfileDetail, String>((ref, id) async {
  final result = await ref.watch(profileDetailRepositoryProvider).getProfileDetail(id);
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final similarProfilesProvider =
    FutureProvider.autoDispose.family<List<MatchProfile>, String>((ref, id) async {
  final result = await ref.watch(profileDetailRepositoryProvider).getSimilarProfiles(id);
  return result.when(success: (data) => data, failure: (f) => throw f);
});
