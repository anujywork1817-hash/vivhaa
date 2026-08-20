import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/admin_models.dart';
import '../../data/api_admin_repository.dart';

final adminDashboardProvider = FutureProvider.autoDispose<AdminDashboardStats>((ref) async {
  final result = await ref.watch(adminRepositoryProvider).getDashboard();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final adminUserSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final adminUserStatusFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) async {
  final search = ref.watch(adminUserSearchProvider);
  final status = ref.watch(adminUserStatusFilterProvider);
  final result = await ref.watch(adminRepositoryProvider).listUsers(status: status, search: search);
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final adminPendingVerificationsProvider =
    FutureProvider.autoDispose<List<AdminVerificationRequest>>((ref) async {
  final result = await ref.watch(adminRepositoryProvider).listPendingVerifications();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final adminPendingReportsProvider = FutureProvider.autoDispose<List<AdminReport>>((ref) async {
  final result = await ref.watch(adminRepositoryProvider).listPendingReports();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

class AdminActions {
  final Ref ref;
  AdminActions(this.ref);

  Future<void> suspendUser(String id) async {
    await ref.read(adminRepositoryProvider).suspendUser(id);
    ref.invalidate(adminUsersProvider);
    ref.invalidate(adminDashboardProvider);
  }

  Future<void> activateUser(String id) async {
    await ref.read(adminRepositoryProvider).activateUser(id);
    ref.invalidate(adminUsersProvider);
    ref.invalidate(adminDashboardProvider);
  }

  Future<void> approveVerification(String id, {String? notes}) async {
    await ref.read(adminRepositoryProvider).approveVerification(id, notes: notes);
    ref.invalidate(adminPendingVerificationsProvider);
    ref.invalidate(adminDashboardProvider);
  }

  Future<void> rejectVerification(String id, {String? notes}) async {
    await ref.read(adminRepositoryProvider).rejectVerification(id, notes: notes);
    ref.invalidate(adminPendingVerificationsProvider);
    ref.invalidate(adminDashboardProvider);
  }

  Future<void> resolveReport(String id, String status, {String? notes, bool suspendUser = false}) async {
    await ref
        .read(adminRepositoryProvider)
        .resolveReport(id, status, notes: notes, suspendUser: suspendUser);
    ref.invalidate(adminPendingReportsProvider);
    ref.invalidate(adminDashboardProvider);
  }
}

final adminActionsProvider = Provider((ref) => AdminActions(ref));
