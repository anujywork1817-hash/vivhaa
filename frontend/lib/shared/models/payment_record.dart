/// One row of `/payments/history` — a completed or attempted checkout.
class PaymentRecord {
  final String id;
  final String planCode;
  final String planName;
  final int amountINR;
  final int discountINR;
  final String status;
  final DateTime createdAt;
  final DateTime? paidAt;

  const PaymentRecord({
    required this.id,
    required this.planCode,
    required this.planName,
    required this.amountINR,
    required this.discountINR,
    required this.status,
    required this.createdAt,
    this.paidAt,
  });

  bool get isPaid => status == 'paid';
}
