import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/call_history_entry.dart';
import '../domain/call_repository.dart';

class ApiCallRepository implements CallRepository {
  static const int historyPageSize = 20;

  final ApiClient _client;

  ApiCallRepository(this._client);

  @override
  Future<ApiResult<List<IceServer>>> getIceServers() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.iceServers);
      final data = response.data['data'] as Map<String, dynamic>;
      final rows = (data['ice_servers'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows
          .map((json) => IceServer(
                urls: (json['urls'] as List).cast<String>(),
                username: json['username'] as String?,
                credential: json['credential'] as String?,
              ))
          .toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<CallHistoryEntry>>> getCallHistory({int page = 0}) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.callHistory, queryParameters: {
        'page': page + 1,
        'limit': historyPageSize,
      });
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(CallHistoryEntry.fromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }
}

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return ApiCallRepository(ref.watch(apiClientProvider));
});
