import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';

class UnlockCheckoutResult {
  final bool unlocked;
  final String? paymentId;
  final String? orderId;
  final int? amountPaise;
  final String? currency;
  final String? razorpayKeyId;

  const UnlockCheckoutResult({
    required this.unlocked,
    this.paymentId,
    this.orderId,
    this.amountPaise,
    this.currency,
    this.razorpayKeyId,
  });
}

/// Backs the one-time ₹1 unlock paywall (see internal/unlock on the
/// backend) — a separate flow from [ApiPaymentsRepository]'s plan-based
/// subscription checkout, hitting /unlock/* instead of /payments/*.
class ApiUnlockRepository {
  final ApiClient _client;
  ApiUnlockRepository(this._client);

  Future<ApiResult<bool>> getStatus() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.unlockStatus);
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(data['unlocked'] as bool? ?? false);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Future<ApiResult<UnlockCheckoutResult>> checkout() async {
    try {
      final response = await _client.dio.post(ApiEndpoints.unlockCheckout);
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(UnlockCheckoutResult(
        unlocked: data['unlocked'] as bool? ?? false,
        paymentId: data['payment_id'] as String?,
        orderId: data['razorpay_order_id'] as String?,
        amountPaise: (data['amount_paise'] as num?)?.toInt(),
        currency: data['currency'] as String?,
        razorpayKeyId: data['razorpay_key_id'] as String?,
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Future<ApiResult<bool>> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final response = await _client.dio.post(ApiEndpoints.unlockVerify, data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(data['unlocked'] as bool? ?? false);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }
}

final unlockRepositoryProvider = Provider<ApiUnlockRepository>((ref) {
  return ApiUnlockRepository(ref.watch(apiClientProvider));
});
