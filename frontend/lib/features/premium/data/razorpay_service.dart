import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class PaymentSuccess {
  final String paymentId;
  final String orderId;
  final String signature;
  const PaymentSuccess({required this.paymentId, required this.orderId, required this.signature});
}

class PaymentFailure {
  final int? code;
  final String message;
  const PaymentFailure({this.code, required this.message});
}

/// Thin wrapper around the real `razorpay_flutter` SDK — opens Razorpay's
/// actual hosted checkout (cards/UPI/wallets/netbanking) against a real
/// order created server-side by `POST /payments/checkout` (see
/// [ApiPaymentsRepository]), not a client-computed amount.
///
/// Razorpay's Flutter plugin only supports Android and iOS (there's no
/// web implementation), so [open] refuses to run on web with a clear
/// [PaymentFailure] rather than silently doing nothing or faking success.
class RazorpayService {
  Razorpay? _razorpay;

  Future<PaymentSuccess> open({
    required String orderId,
    required String keyId,
    required int amountInPaise,
    required String description,
    required String contactName,
    String? contactEmail,
    String? contactPhone,
  }) {
    if (kIsWeb) {
      return Future.error(const PaymentFailure(
        message:
            "Razorpay's Flutter checkout isn't available on web (Android/iOS only). Run this on a device or emulator to test payment.",
      ));
    }

    final completer = Completer<PaymentSuccess>();
    _razorpay = Razorpay();

    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
      completer.complete(PaymentSuccess(
        paymentId: response.paymentId ?? '',
        orderId: response.orderId ?? orderId,
        signature: response.signature ?? '',
      ));
      _dispose();
    });

    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      completer.completeError(PaymentFailure(
        code: response.code,
        message: response.message ?? 'Payment failed. Please try again.',
      ));
      _dispose();
    });

    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
      completer.completeError(PaymentFailure(
        message: 'Opened external wallet "${response.walletName}" — complete payment there.',
      ));
      _dispose();
    });

    _razorpay!.open({
      'key': keyId,
      'order_id': orderId,
      'amount': amountInPaise,
      'name': 'Vivah',
      'description': description,
      'prefill': {
        if (contactEmail != null) 'email': contactEmail,
        if (contactPhone != null) 'contact': contactPhone,
      },
      'theme': {'color': '#D64264'},
    });

    return completer.future;
  }

  void _dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}
