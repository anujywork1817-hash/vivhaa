import '../../../core/api/api_result.dart';
import '../../../shared/models/match_profile.dart';

abstract class ShortlistRepository {
  Future<ApiResult<List<String>>> getShortlistedProfileIds();
  Future<ApiResult<List<MatchProfile>>> getShortlisted();
  Future<ApiResult<void>> add(String profileId);
  Future<ApiResult<void>> remove(String profileId);
}
