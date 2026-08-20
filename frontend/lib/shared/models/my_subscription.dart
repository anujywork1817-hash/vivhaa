/// Mirrors `/subscriptions/me` — the caller's current plan, which is
/// always "free" (no `startsAt`/`endsAt`) unless a paid plan is active.
class MySubscription {
  final String status;
  final String planCode;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const MySubscription({
    required this.status,
    required this.planCode,
    this.startsAt,
    this.endsAt,
  });

  bool get isPremium => planCode != 'free';
}
