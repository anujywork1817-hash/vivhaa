import '../../../core/api/api_result.dart';
import '../../../shared/models/admin_models.dart';

abstract class AdminRepository {
  Future<ApiResult<AdminDashboardStats>> getDashboard();

  Future<ApiResult<List<AdminUser>>> listUsers({String? status, String? search});
  Future<ApiResult<AdminUser>> suspendUser(String id);
  Future<ApiResult<AdminUser>> activateUser(String id);

  Future<ApiResult<List<AdminVerificationRequest>>> listPendingVerifications();
  Future<ApiResult<void>> approveVerification(String id, {String? notes});
  Future<ApiResult<void>> rejectVerification(String id, {String? notes});

  Future<ApiResult<List<AdminReport>>> listPendingReports();
  Future<ApiResult<void>> resolveReport(String id, String status, {String? notes, bool suspendUser = false});
}
