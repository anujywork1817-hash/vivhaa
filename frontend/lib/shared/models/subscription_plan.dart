/// Mirrors the real matrimony_backend `/subscriptions/plans` response —
/// no fictitious "original price"/discount/badge marketing data, since
/// none of that exists on the backend.
class SubscriptionPlan {
  final String code;
  final String name;
  final int priceINR;
  final int durationDays;
  final bool hasChat;
  final bool hasUnlimitedInterests;
  final bool hasViewContact;

  /// Ordered tier rank from the backend — free=0, Monthly=1, Quarterly=2,
  /// Yearly=3. Used to compute "is this plan an upgrade from that plan"
  /// generically (target.tierRank > current.tierRank) instead of
  /// hardcoding per-plan-code comparisons on the client.
  final int tierRank;

  const SubscriptionPlan({
    required this.code,
    required this.name,
    required this.priceINR,
    required this.durationDays,
    this.hasChat = false,
    this.hasUnlimitedInterests = false,
    this.hasViewContact = false,
    this.tierRank = 0,
  });

  String get durationLabel {
    if (durationDays % 365 == 0) {
      final years = durationDays ~/ 365;
      return years == 1 ? '12 months' : '$years years';
    }
    if (durationDays % 30 == 0) {
      final months = durationDays ~/ 30;
      return months == 1 ? '1 month' : '$months months';
    }
    return '$durationDays days';
  }
}
