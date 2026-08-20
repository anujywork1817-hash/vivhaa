import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_result.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_blocked_users_repository.dart';

final blockedUsersListProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(blockedUsersRepositoryProvider).getBlocked();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

class BlockedUsersActions {
  final Ref ref;
  BlockedUsersActions(this.ref);

  Future<ApiResult<void>> block(String profileId) async {
    final result = await ref.read(blockedUsersRepositoryProvider).block(profileId);
    if (result.isSuccess) ref.invalidate(blockedUsersListProvider);
    return result;
  }

  Future<ApiResult<void>> unblock(String profileId) async {
    final result = await ref.read(blockedUsersRepositoryProvider).unblock(profileId);
    if (result.isSuccess) ref.invalidate(blockedUsersListProvider);
    return result;
  }
}

final blockedUsersActionsProvider = Provider((ref) => BlockedUsersActions(ref));
