import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/my_subscription.dart';
import '../../../../shared/models/payment_record.dart';
import '../../../../shared/models/subscription_plan.dart';
import '../../data/api_payments_repository.dart';
import '../../data/api_subscriptions_repository.dart';

final premiumPlansProvider = FutureProvider.autoDispose<List<SubscriptionPlan>>((ref) async {
  final result = await ref.watch(subscriptionsRepositoryProvider).getPlans();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

/// The caller's current plan — invalidated right after a successful
/// purchase (see order_summary_screen.dart) so the Premium tab and any
/// other UI reading this reflects the new plan immediately instead of
/// still showing "Upgrade to Premium" after a payment that already went
/// through on the backend.
final mySubscriptionProvider = FutureProvider.autoDispose<MySubscription>((ref) async {
  final result = await ref.watch(subscriptionsRepositoryProvider).getMine();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

/// The caller's real billing history — used by the Premium Membership
/// screen, newest first.
final paymentHistoryProvider = FutureProvider.autoDispose<List<PaymentRecord>>((ref) async {
  final result = await ref.watch(paymentsRepositoryProvider).getHistory();
  return result.when(success: (data) => data, failure: (f) => throw f);
});
