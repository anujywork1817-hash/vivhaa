import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/match_profile.dart';

/// Backs the free "hook" swipe deck shown right after onboarding: the
/// fixed 10 male + 10 female is_demo profiles from GET /demo/swipe-deck
/// (see internal/demo on the backend). Mapped into the same [MatchProfile]
/// model the real Discover deck uses so discover_screen's card widgets
/// could be reused verbatim if ever consolidated.
class ApiDemoRepository {
  final ApiClient _client;
  ApiDemoRepository(this._client);

  Future<ApiResult<List<MatchProfile>>> getSwipeDeck() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.demoSwipeDeck);
      final rows = (response.data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final profiles = rows.map((j) {
        return MatchProfile(
          id: j['profile_id'] as String,
          name: j['full_name'] as String? ?? 'Member',
          age: (j['age'] as num?)?.toInt() ?? 0,
          heightCm: (j['height_cm'] as num?)?.toInt() ?? 165,
          city: j['city'] as String? ?? '',
          state: j['state'] as String?,
          motherTongue: j['mother_tongue'] as String?,
          profession: j['occupation'] as String? ?? '',
          education: j['education'] as String? ?? '',
          religion: j['religion'] as String? ?? '',
          maritalStatus: j['marital_status'] as String? ?? 'Never Married',
          diet: j['diet'] as String? ?? 'Vegetarian',
          photoSeed: j['photo_url'] as String?,
        );
      }).toList();
      return ApiResult.success(profiles);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }
}

final demoRepositoryProvider = Provider<ApiDemoRepository>((ref) {
  return ApiDemoRepository(ref.watch(apiClientProvider));
});
