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
///
/// Deliberately NOT `.autoDispose`: every reader (MenuScreen, the Inbox
/// tab, ChatWindowScreen) falls back to `isPremium: false` while this is
/// still loading — the only sane default before the real answer is known,
/// since gating premium-only UI behind an *unconfirmed* "yes" would leak
/// the paid feature to free members. With autoDispose this provider gets
/// torn down the moment its last watcher unmounts (e.g. closing the
/// hamburger Menu) and starts over from that loading state on every
/// single reopen — so a genuinely premium member saw the free "Upgrade
/// Now" bar flash for the ~1s the refetch took, every single time they
/// opened the menu. Kept alive for the app session instead: it loads once
/// and every reader shares that cached, already-resolved value from then
/// on. Purchases still update it immediately via the explicit
/// `ref.invalidate` in order_summary_screen.dart.
final mySubscriptionProvider = FutureProvider<MySubscription>((ref) async {
  final result = await ref.watch(subscriptionsRepositoryProvider).getMine();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

/// The caller's real billing history — used by the Premium Membership
/// screen, newest first.
final paymentHistoryProvider = FutureProvider.autoDispose<List<PaymentRecord>>((ref) async {
  final result = await ref.watch(paymentsRepositoryProvider).getHistory();
  return result.when(success: (data) => data, failure: (f) => throw f);
});
