import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/mapping/profile_enum_mapping.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/models/match_profile.dart';
import '../domain/dashboard_repository.dart';

/// Talks to the real matrimony_backend endpoints backing the dashboard.
/// There's no dedicated "new members" endpoint on the backend, so
/// [getNewMembers] reuses the search endpoint with no filters — it sorts
/// by `created_at desc` by default, which is exactly "newest joined".
class ApiDashboardRepository implements DashboardRepository {
  final ApiClient _client;

  ApiDashboardRepository(this._client);

  @override
  Future<ApiResult<List<MatchProfile>>> getTodayMatches() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.dailyMatches);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromMatchJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<MatchProfile>>> getRecommendedMatches() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.recommendedMatches);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromMatchJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<MatchProfile>>> getNewMembers() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.search, queryParameters: {'limit': 10});
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromSearchJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<MatchProfile>>> getAllMatches() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.allMatches);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromMatchJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<MatchProfile>>> getNearbyMatches({double? radiusKm}) async {
    try {
      final response = await _client.dio.get(
        ApiEndpoints.nearbyMatches,
        queryParameters: radiusKm != null ? {'radius_km': radiusKm} : null,
      );
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromNearbyJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> updateLocation({required double latitude, required double longitude}) async {
    try {
      await _client.dio.put(ApiEndpoints.updateLocation, data: {
        'latitude': latitude,
        'longitude': longitude,
      });
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<AppNotification>>> getNotifications() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.notifications);
      final data = response.data['data'] as Map<String, dynamic>;
      final rows = (data['notifications'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_fromNotificationJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> markNotificationRead(String id) async {
    try {
      await _client.dio.put(ApiEndpoints.notificationRead(id));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> markAllNotificationsRead() async {
    try {
      await _client.dio.put(ApiEndpoints.notificationsReadAll);
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  MatchProfile _fromMatchJson(Map<String, dynamic> json) {
    return MatchProfile(
      id: json['profile_id'] as String,
      name: (json['full_name'] as String?) ?? 'Member',
      age: (json['age'] as num?)?.toInt() ?? 0,
      heightCm: (json['height_cm'] as num?)?.toInt() ?? 0,
      city: (json['city'] as String?) ?? '',
      state: json['state'] as String?,
      motherTongue: json['mother_tongue'] as String?,
      profession: (json['occupation'] as String?) ?? '',
      education: (json['education'] as String?) ?? '',
      religion: (json['religion'] as String?) ?? '',
      maritalStatus: maritalStatusLabelFromBackend(json['marital_status'] as String?),
      diet: dietLabelFromBackend(json['diet'] as String?),
      manglik: manglikLabelFromBackend(json['manglik'] as String?),
      photoSeed: json['photo_url'] as String?,
      matchScore: ((json['compatibility_score'] as num?) ?? 0).toDouble(),
    );
  }

  MatchProfile _fromSearchJson(Map<String, dynamic> json) {
    return MatchProfile(
      id: json['profile_id'] as String,
      name: (json['full_name'] as String?) ?? 'Member',
      age: (json['age'] as num?)?.toInt() ?? 0,
      heightCm: (json['height_cm'] as num?)?.toInt() ?? 0,
      city: (json['city'] as String?) ?? '',
      state: json['state'] as String?,
      motherTongue: json['mother_tongue'] as String?,
      profession: (json['occupation'] as String?) ?? '',
      education: (json['education'] as String?) ?? '',
      religion: (json['religion'] as String?) ?? '',
      community: json['community'] as String?,
      maritalStatus: maritalStatusLabelFromBackend(json['marital_status'] as String?),
      diet: dietLabelFromBackend(json['diet'] as String?),
      manglik: manglikLabelFromBackend(json['manglik'] as String?),
      photoSeed: json['photo_url'] as String?,
      isNew: true,
    );
  }

  MatchProfile _fromNearbyJson(Map<String, dynamic> json) {
    final base = _fromMatchJson(json);
    return MatchProfile(
      id: base.id,
      name: base.name,
      age: base.age,
      heightCm: base.heightCm,
      city: base.city,
      state: base.state,
      motherTongue: base.motherTongue,
      profession: base.profession,
      education: base.education,
      religion: base.religion,
      maritalStatus: base.maritalStatus,
      diet: base.diet,
      manglik: base.manglik,
      photoSeed: base.photoSeed,
      matchScore: base.matchScore,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
    );
  }

  AppNotification _fromNotificationJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: _typeFromBackend(json['type'] as String),
      title: json['title'] as String,
      body: (json['body'] as String?) ?? '',
      timestamp: DateTime.parse(json['created_at'] as String),
      read: json['read'] as bool? ?? false,
      data: (json['data'] as Map<String, dynamic>?) ?? const {},
    );
  }

  NotificationType _typeFromBackend(String type) {
    switch (type) {
      case 'interest_received':
      case 'interest_reminder':
        return NotificationType.interest;
      case 'match':
        return NotificationType.match;
      case 'new_message':
      case 'contact_request':
      case 'contact_accepted':
      case 'contact_declined':
        return NotificationType.message;
      default:
        return NotificationType.system;
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return ApiDashboardRepository(ref.watch(apiClientProvider));
});
