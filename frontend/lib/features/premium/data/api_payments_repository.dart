import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/payment_record.dart';
import '../domain/payments_repository.dart';

class ApiPaymentsRepository implements PaymentsRepository {
  final ApiClient _client;

  ApiPaymentsRepository(this._client);

  @override
  Future<ApiResult<CheckoutResult>> checkout(String planCode, {String? couponCode}) async {
    try {
      final response = await _client.dio.post(ApiEndpoints.paymentsCheckout, data: {
        'plan_code': planCode,
        if (couponCode != null && couponCode.trim().isNotEmpty) 'coupon_code': couponCode.trim(),
      });
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(CheckoutResult(
        paymentId: data['payment_id'] as String,
        orderId: data['razorpay_order_id'] as String,
        amountPaise: (data['amount_paise'] as num).toInt(),
        currency: data['currency'] as String,
        razorpayKeyId: data['razorpay_key_id'] as String,
        discountInr: (data['discount_inr'] as num?)?.toInt() ?? 0,
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<VerifyResult>> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final response = await _client.dio.post(ApiEndpoints.paymentsVerify, data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
      final data = response.data['data'] as Map<String, dynamic>;
      final endsAt = data['subscription_ends_at'] as String?;
      return ApiResult.success(VerifyResult(
        status: data['status'] as String,
        planCode: data['subscription_plan'] as String,
        subscriptionEndsAt: (endsAt != null && endsAt.isNotEmpty) ? DateTime.parse(endsAt) : null,
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<PaymentRecord>>> getHistory() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.paymentHistory);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      final records = rows.map((j) {
        final paidAt = j['paid_at'] as String?;
        return PaymentRecord(
          id: j['id'] as String,
          planCode: j['plan_code'] as String? ?? '',
          planName: j['plan_name'] as String? ?? '',
          amountINR: (j['amount_inr'] as num).toInt(),
          discountINR: (j['discount_inr'] as num?)?.toInt() ?? 0,
          status: j['status'] as String,
          createdAt: DateTime.parse(j['created_at'] as String),
          paidAt: (paidAt != null && paidAt.isNotEmpty) ? DateTime.parse(paidAt) : null,
        );
      }).toList();
      return ApiResult.success(records);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return ApiPaymentsRepository(ref.watch(apiClientProvider));
});
