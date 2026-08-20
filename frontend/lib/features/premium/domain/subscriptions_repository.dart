import '../../../core/api/api_result.dart';
import '../../../shared/models/my_subscription.dart';
import '../../../shared/models/subscription_plan.dart';

abstract class SubscriptionsRepository {
  /// Real, purchasable plans — the backend's free plan is excluded since
  /// there's nothing to check out for it.
  Future<ApiResult<List<SubscriptionPlan>>> getPlans();

  /// The caller's current plan (free, unless a paid subscription is active).
  Future<ApiResult<MySubscription>> getMine();
}
