import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/match_profile.dart';
import '../../../shared/models/visitor_record.dart';
import '../domain/visitor_repository.dart';

/// Talks to the real matrimony_backend `GET /visitors` endpoint. The
/// backend only returns a brief (name/city/photo) per visitor, not a full
/// match card, so the remaining [MatchProfile] fields are defaulted.
class ApiVisitorRepository implements VisitorRepository {
  final ApiClient _client;

  ApiVisitorRepository(this._client);

  @override
  Future<ApiResult<List<VisitorRecord>>> getVisitors() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.visitors);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  VisitorRecord _fromJson(Map<String, dynamic> json) {
    return VisitorRecord(
      profile: MatchProfile(
        id: (json['profile_id'] as String?) ?? '',
        name: (json['full_name'] as String?) ?? 'Member',
        age: 0,
        heightCm: 0,
        city: (json['city'] as String?) ?? '',
        profession: '',
        education: '',
        religion: '',
        photoSeed: json['photo_url'] as String?,
      ),
      visitedAt: DateTime.parse(json['visited_at'] as String),
    );
  }
}

final visitorRepositoryProvider = Provider<VisitorRepository>((ref) {
  return ApiVisitorRepository(ref.watch(apiClientProvider));
});
