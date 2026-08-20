import '../../../core/api/api_result.dart';
import '../../../shared/models/match_profile.dart';

abstract class FavouriteRepository {
  Future<ApiResult<List<MatchProfile>>> getFavourites();
  Future<ApiResult<void>> add(String profileId);
  Future<ApiResult<void>> remove(String profileId);
}
