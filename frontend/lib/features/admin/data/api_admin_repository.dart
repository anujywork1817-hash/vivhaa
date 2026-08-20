import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/admin_models.dart';
import '../domain/admin_repository.dart';

/// Talks to the real matrimony_backend `/admin/*` endpoints — all
/// require the caller's account to have `role: admin` server-side; a
/// non-admin token gets a 403 from every one of these calls.
class ApiAdminRepository implements AdminRepository {
  final ApiClient _client;

  ApiAdminRepository(this._client);

  @override
  Future<ApiResult<AdminDashboardStats>> getDashboard() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.adminDashboard);
      final j = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(AdminDashboardStats(
        totalUsers: j['total_users'] as int,
        activeUsers: j['active_users'] as int,
        suspendedUsers: j['suspended_users'] as int,
        newSignupsToday: j['new_signups_today'] as int,
        totalMatches: j['total_matches'] as int,
        totalMessages: j['total_messages'] as int,
        pendingVerifications: j['pending_verifications'] as int,
        pendingReports: j['pending_reports'] as int,
        activeSubscriptions: j['active_subscriptions'] as int,
        revenueInr: (j['revenue_inr'] as num).toInt(),
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<AdminUser>>> listUsers({String? status, String? search}) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.adminUsers, queryParameters: {
        'limit': 100,
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_userFromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<AdminUser>> suspendUser(String id) async {
    try {
      final response = await _client.dio.put(ApiEndpoints.adminSuspendUser(id));
      return ApiResult.success(_userFromJson(response.data['data'] as Map<String, dynamic>));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<AdminUser>> activateUser(String id) async {
    try {
      final response = await _client.dio.put(ApiEndpoints.adminActivateUser(id));
      return ApiResult.success(_userFromJson(response.data['data'] as Map<String, dynamic>));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<AdminVerificationRequest>>> listPendingVerifications() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.adminVerifications);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows
          .map((j) => AdminVerificationRequest(
                id: j['id'] as String,
                userId: j['user_id'] as String,
                documentType: j['document_type'] as String,
                documentUrl: j['document_url'] as String,
                status: j['status'] as String,
                createdAt: DateTime.parse(j['created_at'] as String),
              ))
          .toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> approveVerification(String id, {String? notes}) async {
    try {
      await _client.dio.put(ApiEndpoints.adminApproveVerification(id), data: {'notes': notes});
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> rejectVerification(String id, {String? notes}) async {
    try {
      await _client.dio.put(ApiEndpoints.adminRejectVerification(id), data: {'notes': notes});
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<AdminReport>>> listPendingReports() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.adminReports);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows
          .map((j) => AdminReport(
                id: j['id'] as String,
                reporterUserId: j['reporter_user_id'] as String,
                reportedUserId: j['reported_user_id'] as String,
                reason: j['reason'] as String,
                details: j['details'] as String?,
                status: j['status'] as String,
                createdAt: DateTime.parse(j['created_at'] as String),
              ))
          .toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> resolveReport(String id, String status,
      {String? notes, bool suspendUser = false}) async {
    try {
      await _client.dio.put(ApiEndpoints.adminResolveReport(id), data: {
        'status': status,
        'notes': notes,
        'suspend_user': suspendUser,
      });
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  AdminUser _userFromJson(Map<String, dynamic> j) {
    return AdminUser(
      id: j['id'] as String,
      phone: j['phone'] as String?,
      email: j['email'] as String?,
      phoneVerified: j['phone_verified'] as bool? ?? false,
      emailVerified: j['email_verified'] as bool? ?? false,
      status: j['status'] as String,
      role: j['role'] as String,
      lastLoginAt: (j['last_login_at'] as String?) != null
          ? DateTime.parse(j['last_login_at'] as String)
          : null,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return ApiAdminRepository(ref.watch(apiClientProvider));
});
