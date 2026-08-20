import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/ai_message.dart';
import '../domain/ai_repository.dart';

/// Talks to the real matrimony_backend `/ai/*` endpoints (Groq-backed).
/// If the backend has no `GROQ_API_KEY` configured, every call fails with
/// a clear `ai_not_configured` error (mapped to a normal [AppFailure])
/// rather than pretending to work.
class ApiAiRepository implements AiRepository {
  final ApiClient _client;

  ApiAiRepository(this._client);

  @override
  Future<ApiResult<List<AiMessage>>> getHistory() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.aiMessages);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<AiMessage>> sendMessage(String text) async {
    try {
      final response = await _client.dio.post(ApiEndpoints.aiChat, data: {'message': text});
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromJson(data));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<String>>> getIcebreakers(String profileId) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.aiIcebreakers(profileId));
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success((data['icebreakers'] as List).cast<String>());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<String>> getMatchBlurb(String profileId) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.aiMatchBlurb(profileId));
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(data['blurb'] as String);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  AiMessage _fromJson(Map<String, dynamic> json) {
    return AiMessage(
      id: json['id'] as String,
      role: json['role'] == 'assistant' ? AiMessageRole.assistant : AiMessageRole.user,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['created_at'] as String),
    );
  }
}

final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return ApiAiRepository(ref.watch(apiClientProvider));
});
