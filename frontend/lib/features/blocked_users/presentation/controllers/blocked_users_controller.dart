import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_result.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../../../profile_detail/presentation/controllers/profile_detail_controller.dart';
import '../../data/api_blocked_users_repository.dart';

final blockedUsersListProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(blockedUsersRepositoryProvider).getBlocked();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

class BlockedUsersActions {
  final Ref ref;
  BlockedUsersActions(this.ref);

  /// Every screen a block/unblock can be seen from, refreshed together so
  /// none of them need a manual pull-to-refresh to catch up: the blocked
  /// list itself, this profile's own detail page (block status gates its
  /// chat/call actions), the chat inbox (a block locks/unlocks the thread),
  /// and the sent/received interest lists (a blocked party's pending
  /// interest should disappear immediately, in either direction).
  void _refreshAffected(String profileId) {
    ref.invalidate(blockedUsersListProvider);
    ref.invalidate(profileDetailProvider(profileId));
    ref.invalidate(conversationsProvider);
    ref.invalidate(sentInterestsProvider);
    ref.invalidate(receivedInterestsProvider);
  }

  Future<ApiResult<void>> block(String profileId) async {
    final result = await ref.read(blockedUsersRepositoryProvider).block(profileId);
    if (result.isSuccess) _refreshAffected(profileId);
    return result;
  }

  Future<ApiResult<void>> unblock(String profileId) async {
    final result = await ref.read(blockedUsersRepositoryProvider).unblock(profileId);
    if (result.isSuccess) _refreshAffected(profileId);
    return result;
  }
}

final blockedUsersActionsProvider = Provider((ref) => BlockedUsersActions(ref));
