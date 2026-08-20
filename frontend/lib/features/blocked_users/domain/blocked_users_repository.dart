import '../../../core/api/api_result.dart';
import '../../../shared/models/match_profile.dart';

abstract class BlockedUsersRepository {
  Future<ApiResult<List<MatchProfile>>> getBlocked();
  Future<ApiResult<void>> block(String profileId);
  Future<ApiResult<void>> unblock(String profileId);
}
