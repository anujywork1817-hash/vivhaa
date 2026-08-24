import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/match_profile.dart';
import '../../../shared/models/profile_detail.dart';
import '../domain/profile_detail_repository.dart';

/// Talks to the real matrimony_backend `GET /profiles/:id` (+ `/contact`)
/// and `POST /reports/:profileId`.
///
/// [getSimilarProfiles] has no backend equivalent yet — "similar to this
/// specific profile" isn't a query the recommendation engine supports
/// (it only scores matches against *your own* preferences via
/// /matches/recommended). Left throwing so it's obviously unwired rather
/// than silently returning an empty list.
class ApiProfileDetailRepository implements ProfileDetailRepository {
  final ApiClient _client;

  ApiProfileDetailRepository(this._client);

  @override
  Future<ApiResult<ProfileDetail>> getProfileDetail(String id) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.profileById(id));
      final j = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_toProfileDetail(id, j));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<MatchProfile>>> getSimilarProfiles(String id, {int count = 6}) async {
    return ApiResult.failure(AppFailure.unknown(
      'Similar profiles aren\'t available yet — this needs the recommendation '
      'engine to support "similar to profile X", which /matches/recommended '
      'doesn\'t do (it only scores against your own preferences).',
    ));
  }

  @override
  Future<ApiResult<void>> reportProfile(String id, String reason, {String? details}) async {
    try {
      await _client.dio.post(
        ApiEndpoints.reportUser(id),
        data: {'reason': reason, if (details != null) 'details': details},
      );
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<ContactInfo>> getContact(String id) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.profileContact(id));
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(ContactInfo(
        phone: data['phone'] as String?,
        email: data['email'] as String?,
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  ProfileDetail _toProfileDetail(String id, Map<String, dynamic> j) {
    final photos = (j['photos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final fullName = j['full_name'] as String? ?? 'Member';
    final dob = j['date_of_birth'] as String?;
    final age = dob == null ? 0 : (DateTime.tryParse(dob) == null ? 0 : _ageFrom(DateTime.parse(dob)));

    final summary = MatchProfile(
      id: id,
      name: fullName,
      age: age,
      heightCm: (j['height_cm'] as num?)?.toInt() ?? 0,
      city: j['city'] as String? ?? '',
      profession: j['occupation'] as String? ?? '',
      education: j['education'] as String? ?? '',
      religion: j['religion'] as String? ?? '',
      maritalStatus: (j['marital_status'] as String? ?? 'never_married').replaceAll('_', ' '),
      diet: (j['diet'] as String? ?? 'vegetarian').replaceAll('_', ' '),
      community: j['community'] as String?,
      // Not returned by GET /profiles/:id — no per-viewer verification
      // badge exists server-side today (only account-level phone/email
      // verification, which this endpoint doesn't expose).
      verified: false,
      photoSeed: photos.isNotEmpty ? (photos.first['url'] as String?) : null,
    );

    return ProfileDetail(
      summary: summary,
      photoIds: photos.map((p) => p['url'] as String).toList(),
      about: j['about_me'] as String? ?? '',
      fatherOccupation: j['father_occupation'] as String? ?? '',
      motherOccupation: j['mother_occupation'] as String? ?? '',
      // Backend stores one combined sibling count, not a brothers/sisters
      // split — shown as brothers with sisters zeroed rather than
      // inventing a split that isn't real.
      brothers: (j['siblings_count'] as num?)?.toInt() ?? 0,
      sisters: 0,
      familyType: (j['family_type'] as String? ?? '').replaceAll('_', ' '),
      // Astrology (rashi/nakshatra) and family "values" (as opposed to
      // financial status) aren't tracked by the backend at all.
      familyValues: '',
      smoking: (j['smoking'] as String? ?? '').replaceAll('_', ' '),
      drinking: (j['drinking'] as String? ?? '').replaceAll('_', ' '),
      rashi: '',
      nakshatra: '',
      partnerPreferenceSummary: '',
      idVerified: false,
      phoneVerified: false,
      photoVerified: false,
    );
  }

  int _ageFrom(DateTime dob) {
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) years--;
    return years;
  }

}

final profileDetailRepositoryProvider = Provider<ProfileDetailRepository>((ref) {
  return ApiProfileDetailRepository(ref.watch(apiClientProvider));
});
