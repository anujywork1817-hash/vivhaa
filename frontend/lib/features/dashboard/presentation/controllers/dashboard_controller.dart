import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_result.dart';
import '../../../../shared/models/app_notification.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_dashboard_repository.dart';

final todayMatchesProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(dashboardRepositoryProvider).getTodayMatches();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final newMembersProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(dashboardRepositoryProvider).getNewMembers();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final recommendedMatchesProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(dashboardRepositoryProvider).getRecommendedMatches();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

/// Holds the notification list as mutable state (rather than a plain
/// FutureProvider) so the Notifications screen can flip read/unread flags
/// optimistically — on tap or "mark all as read" — without waiting on a
/// refetch, and roll back in place if the API call fails.
class NotificationsController extends AutoDisposeAsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    final result = await ref.watch(dashboardRepositoryProvider).getNotifications();
    return result.when(success: (data) => data, failure: (f) => throw f);
  }

  Future<void> markAsRead(String id) async {
    final previous = state.valueOrNull;
    if (previous == null) return;
    final target = previous.firstWhere((n) => n.id == id, orElse: () => previous.first);
    if (target.read) return;

    state = AsyncData([
      for (final n in previous) if (n.id == id) n.copyWith(read: true) else n,
    ]);

    final result = await ref.read(dashboardRepositoryProvider).markNotificationRead(id);
    result.when(
      success: (_) {},
      failure: (_) => state = AsyncData(previous),
    );
  }

  Future<ApiResult<void>> markAllAsRead() async {
    final previous = state.valueOrNull;
    if (previous == null) return const ApiResult.success(null);

    state = AsyncData([for (final n in previous) n.copyWith(read: true)]);

    final result = await ref.read(dashboardRepositoryProvider).markAllNotificationsRead();
    result.when(
      success: (_) => ref.invalidateSelf(),
      failure: (_) => state = AsyncData(previous),
    );
    return result;
  }
}

final notificationsProvider =
    AsyncNotifierProvider.autoDispose<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return notifications.where((n) => !n.read).length;
});
