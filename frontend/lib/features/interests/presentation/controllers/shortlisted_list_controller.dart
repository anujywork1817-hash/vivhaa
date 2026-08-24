import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_shortlist_repository.dart';

/// The current user's shortlisted profiles, for the Shortlisted list
/// screen — mirrors favouritesListProvider's pattern exactly.
final shortlistedListProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(shortlistRepositoryProvider).getShortlisted();
  return result.when(success: (data) => data, failure: (f) => throw f);
});
