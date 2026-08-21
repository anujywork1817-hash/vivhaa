import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/mapping/profile_enum_mapping.dart';
import '../../../shared/models/interest.dart';
import '../../../shared/models/match_profile.dart';
import '../domain/interest_repository.dart';

/// Talks to the real matrimony_backend `/interests/*` endpoints.
class ApiInterestRepository implements InterestRepository {
  final ApiClient _client;

  ApiInterestRepository(this._client);

  @override
  Future<ApiResult<List<InterestRecord>>> getSent() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.interestsSent);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map((r) => _fromJson(r, InterestDirection.sent)).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<InterestRecord>>> getReceived() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.interestsReceived);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map((r) => _fromJson(r, InterestDirection.received)).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<InterestRecord>>> getDeleted() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.interestsDeleted);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      // Direction isn't meaningful for a deleted item (the list mixes both
      // ways round); sent is used as a neutral default since the card only
      // reads the profile and status.
      return ApiResult.success(
          rows.map((r) => _fromJson(r, InterestDirection.sent)).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<InterestRecord>> sendInterest(MatchProfile profile) async {
    try {
      final response = await _client.dio.post(ApiEndpoints.expressInterest(profile.id));
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(InterestRecord(
        id: data['id'] as String,
        profile: profile,
        direction: InterestDirection.sent,
        status: _statusFromJson(data['status'] as String),
        timestamp: DateTime.parse(data['created_at'] as String),
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<InterestRecord>> respond(String interestId, bool accept) async {
    try {
      final response = await _client.dio.put(
        accept ? ApiEndpoints.acceptInterest(interestId) : ApiEndpoints.declineInterest(interestId),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromJson(data, InterestDirection.received));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> withdraw(String interestId) async {
    try {
      await _client.dio.delete(ApiEndpoints.deleteInterest(interestId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> remind(String interestId) async {
    try {
      await _client.dio.put(ApiEndpoints.remindInterest(interestId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  InterestRecord _fromJson(Map<String, dynamic> json, InterestDirection direction) {
    return InterestRecord(
      id: json['id'] as String,
      profile: MatchProfile(
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
        state: json['state'] as String?,
        motherTongue: json['mother_tongue'] as String?,
        community: json['community'] as String?,
      ),
      direction: direction,
      status: _statusFromJson(json['status'] as String),
      timestamp: DateTime.parse(json['created_at'] as String),
      otherGender: json['gender'] as String?,
      viewedAt: (json['viewed_at'] as String?) != null
          ? DateTime.tryParse(json['viewed_at'] as String)
          : null,
      // Whichever end of the interest isn't the caller.
      partnerUserId: direction == InterestDirection.sent
          ? json['receiver_user_id'] as String?
          : json['sender_user_id'] as String?,
    );
  }

  InterestStatus _statusFromJson(String status) {
    switch (status) {
      case 'accepted':
        return InterestStatus.accepted;
      case 'declined':
        return InterestStatus.declined;
      default:
        return InterestStatus.pending;
    }
  }
}

final interestRepositoryProvider = Provider<InterestRepository>((ref) {
  return ApiInterestRepository(ref.watch(apiClientProvider));
});
