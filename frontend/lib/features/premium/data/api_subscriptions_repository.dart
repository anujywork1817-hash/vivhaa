import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/my_subscription.dart';
import '../../../shared/models/subscription_plan.dart';
import '../domain/subscriptions_repository.dart';

class ApiSubscriptionsRepository implements SubscriptionsRepository {
  final ApiClient _client;

  ApiSubscriptionsRepository(this._client);

  @override
  Future<ApiResult<List<SubscriptionPlan>>> getPlans() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.subscriptionPlans);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      // Includes the free plan (tier_rank 0) — needed so tier-upgrade
      // comparisons and the Basic comparison card have real data for it,
      // not just the paid ones. Screens that only want purchasable plans
      // filter priceINR > 0 themselves (see _PlanSelector).
      final plans = rows.map(_fromJson).toList();
      return ApiResult.success(plans);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<MySubscription>> getMine() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.mySubscription);
      final data = response.data['data'] as Map<String, dynamic>;
      final startsAt = data['starts_at'] as String?;
      final endsAt = data['ends_at'] as String?;
      return ApiResult.success(MySubscription(
        status: data['status'] as String,
        planCode: data['plan_code'] as String,
        startsAt: (startsAt != null && startsAt.isNotEmpty) ? DateTime.parse(startsAt) : null,
        endsAt: (endsAt != null && endsAt.isNotEmpty) ? DateTime.parse(endsAt) : null,
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  SubscriptionPlan _fromJson(Map<String, dynamic> json) {
    final features = (json['features'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SubscriptionPlan(
      code: json['code'] as String,
      name: json['name'] as String,
      priceINR: (json['price_inr'] as num).toInt(),
      durationDays: (json['duration_days'] as num).toInt(),
      hasChat: features['chat'] == true,
      hasUnlimitedInterests: features['unlimited_interests'] == true,
      hasViewContact: features['view_contact'] == true,
      tierRank: (json['tier_rank'] as num?)?.toInt() ?? 0,
    );
  }
}

final subscriptionsRepositoryProvider = Provider<SubscriptionsRepository>((ref) {
  return ApiSubscriptionsRepository(ref.watch(apiClientProvider));
});
