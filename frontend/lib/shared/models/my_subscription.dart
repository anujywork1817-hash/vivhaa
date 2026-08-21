/// Launch switch mirroring the backend's `PREMIUM_GATING_ENABLED` env var
/// (see `subscriptions.gatingEnabled` in the Go backend): the app is
/// meant to run fully free at first, so every premium-gated UI element
/// (upgrade banners, contact-reveal prompts, the chat paywall) is hidden
/// while this is false, regardless of the caller's real plan. Flip this
/// back to true — together with the backend env var — when premium is
/// ready to actually launch; nothing else needs to change.
const bool kPremiumFeatureEnabled = false;

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

  bool get isPremium => !kPremiumFeatureEnabled || planCode != 'free';
}
