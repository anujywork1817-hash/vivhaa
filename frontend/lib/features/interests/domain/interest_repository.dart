import '../../../core/api/api_result.dart';
import '../../../shared/models/interest.dart';
import '../../../shared/models/match_profile.dart';

abstract class InterestRepository {
  Future<ApiResult<List<InterestRecord>>> getSent();
  Future<ApiResult<List<InterestRecord>>> getReceived();

  /// Interests the caller soft-deleted, in either direction.
  Future<ApiResult<List<InterestRecord>>> getDeleted();
  Future<ApiResult<InterestRecord>> sendInterest(MatchProfile profile);
  Future<ApiResult<InterestRecord>> respond(String interestId, bool accept);
  Future<ApiResult<void>> withdraw(String interestId);

  /// Re-notifies the recipient about a request that's still pending.
  Future<ApiResult<void>> remind(String interestId);
}
