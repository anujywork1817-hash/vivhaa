import '../../../core/api/api_result.dart';
import '../../../shared/models/payment_record.dart';

class CheckoutResult {
  final String paymentId;
  final String orderId;
  final int amountPaise;
  final String currency;
  final String razorpayKeyId;
  final int discountInr;

  const CheckoutResult({
    required this.paymentId,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.razorpayKeyId,
    required this.discountInr,
  });
}

class VerifyResult {
  final String status;
  final String planCode;
  final DateTime? subscriptionEndsAt;

  const VerifyResult({required this.status, required this.planCode, this.subscriptionEndsAt});
}

abstract class PaymentsRepository {
  /// Creates a real Razorpay order for [planCode] (optionally discounted by
  /// [couponCode]) — the amount actually charged is decided server-side,
  /// never computed on the client.
  Future<ApiResult<CheckoutResult>> checkout(String planCode, {String? couponCode});

  /// Verifies a completed Razorpay checkout's signature server-side and,
  /// if valid, activates the subscription tied to that order.
  Future<ApiResult<VerifyResult>> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  });

  /// The caller's real payment history, newest first.
  Future<ApiResult<List<PaymentRecord>>> getHistory();
}
