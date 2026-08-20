import '../../../core/api/api_result.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/models/match_profile.dart';

abstract class DashboardRepository {
  Future<ApiResult<List<MatchProfile>>> getTodayMatches();
  Future<ApiResult<List<MatchProfile>>> getNewMembers();
  Future<ApiResult<List<MatchProfile>>> getRecommendedMatches();
  Future<ApiResult<List<MatchProfile>>> getAllMatches();
  Future<ApiResult<List<MatchProfile>>> getNearbyMatches({double? radiusKm});
  Future<ApiResult<void>> updateLocation({required double latitude, required double longitude});
  Future<ApiResult<List<AppNotification>>> getNotifications();
  Future<ApiResult<void>> markNotificationRead(String id);
  Future<ApiResult<void>> markAllNotificationsRead();
}
