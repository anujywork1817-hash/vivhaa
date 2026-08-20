import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/match_profile.dart';
import '../domain/blocked_users_repository.dart';

/// Talks to the real matrimony_backend `/blocked/*` endpoints.
class ApiBlockedUsersRepository implements BlockedUsersRepository {
  final ApiClient _client;

  ApiBlockedUsersRepository(this._client);

  @override
  Future<ApiResult<List<MatchProfile>>> getBlocked() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.blocked);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> block(String profileId) async {
    try {
      await _client.dio.post(ApiEndpoints.blockUser(profileId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> unblock(String profileId) async {
    try {
      await _client.dio.delete(ApiEndpoints.blockUser(profileId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  MatchProfile _fromJson(Map<String, dynamic> json) {
    return MatchProfile(
      id: (json['profile_id'] as String?) ?? '',
      name: (json['full_name'] as String?) ?? 'Member',
      age: 0,
      heightCm: 0,
      city: (json['city'] as String?) ?? '',
      profession: '',
      education: '',
      religion: '',
      photoSeed: json['photo_url'] as String?,
    );
  }
}

final blockedUsersRepositoryProvider = Provider<BlockedUsersRepository>((ref) {
  return ApiBlockedUsersRepository(ref.watch(apiClientProvider));
});
