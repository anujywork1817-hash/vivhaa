import '../../../core/api/api_result.dart';
import '../../../shared/models/match_profile.dart';

/// Mirrors backend/internal/blocked/dto.go's StatusResponse — the block
/// relationship between the caller and a profile, checked independently in
/// each direction so the UI can tell "you blocked them" (show Unblock)
/// apart from "they blocked you" (no action available, and the profile
/// itself won't even load — see profiles.Service.checkNotBlocked).
class BlockStatus {
  final bool isBlockedByMe;
  final bool hasBlockedMe;
  const BlockStatus({required this.isBlockedByMe, required this.hasBlockedMe});
}

abstract class BlockedUsersRepository {
  Future<ApiResult<List<MatchProfile>>> getBlocked();
  Future<ApiResult<BlockStatus>> status(String profileId);
  Future<ApiResult<void>> block(String profileId);
  Future<ApiResult<void>> unblock(String profileId);
}
