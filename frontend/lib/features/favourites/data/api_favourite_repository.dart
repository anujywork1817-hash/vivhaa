import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/mapping/profile_enum_mapping.dart';
import '../../../shared/models/match_profile.dart';
import '../domain/favourite_repository.dart';

/// Talks to the real matrimony_backend `/favourites/*` endpoints.
class ApiFavouriteRepository implements FavouriteRepository {
  final ApiClient _client;

  ApiFavouriteRepository(this._client);

  @override
  Future<ApiResult<List<MatchProfile>>> getFavourites() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.favourites);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> add(String profileId) async {
    try {
      await _client.dio.post(ApiEndpoints.favourite(profileId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> remove(String profileId) async {
    try {
      await _client.dio.delete(ApiEndpoints.favourite(profileId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  MatchProfile _fromJson(Map<String, dynamic> json) {
    return MatchProfile(
      id: (json['profile_id'] as String?) ?? '',
      name: (json['full_name'] as String?) ?? 'Member',
      age: (json['age'] as num?)?.toInt() ?? 0,
      heightCm: (json['height_cm'] as num?)?.toInt() ?? 0,
      city: (json['city'] as String?) ?? '',
      profession: (json['occupation'] as String?) ?? '',
      education: (json['education'] as String?) ?? '',
      religion: (json['religion'] as String?) ?? '',
      maritalStatus: maritalStatusLabelFromBackend(json['marital_status'] as String?),
      diet: dietLabelFromBackend(json['diet'] as String?),
      manglik: manglikLabelFromBackend(json['manglik'] as String?),
      photoSeed: json['photo_url'] as String?,
    );
  }
}

final favouriteRepositoryProvider = Provider<FavouriteRepository>((ref) {
  return ApiFavouriteRepository(ref.watch(apiClientProvider));
});
