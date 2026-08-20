import '../../../core/api/api_result.dart';

abstract class ShortlistRepository {
  Future<ApiResult<List<String>>> getShortlistedProfileIds();
  Future<ApiResult<void>> add(String profileId);
  Future<ApiResult<void>> remove(String profileId);
}
