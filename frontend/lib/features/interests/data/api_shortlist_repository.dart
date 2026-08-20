import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../domain/shortlist_repository.dart';

/// Talks to the real matrimony_backend `/shortlisted/*` endpoints.
class ApiShortlistRepository implements ShortlistRepository {
  final ApiClient _client;

  ApiShortlistRepository(this._client);

  @override
  Future<ApiResult<List<String>>> getShortlistedProfileIds() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.shortlisted);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      final ids = rows
          .map((r) => r['profile_id'] as String?)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
      return ApiResult.success(ids);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> add(String profileId) async {
    try {
      await _client.dio.post(ApiEndpoints.shortlist(profileId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> remove(String profileId) async {
    try {
      await _client.dio.delete(ApiEndpoints.shortlist(profileId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }
}

final shortlistRepositoryProvider = Provider<ShortlistRepository>((ref) {
  return ApiShortlistRepository(ref.watch(apiClientProvider));
});
