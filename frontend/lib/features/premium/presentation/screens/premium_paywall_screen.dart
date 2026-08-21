import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/subscription_plan.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../controllers/premium_controller.dart';
import '../plan_tier.dart';
import 'premium_membership_screen.dart';

/// Plan picker. Reused as the post-signup upsell (with Skip going straight
/// to the finished profile), as the Premium tab in the main app for a free
/// member (no Skip, just Continue), and — with [forceShowPlans] — as the
/// "Change Plan" destination for an already-premium member who wants to
/// switch durations, at which point [PremiumMembershipScreen] would
/// otherwise be shown instead.
class PremiumPaywallScreen extends ConsumerStatefulWidget {
  final bool showSkip;
  final bool forceShowPlans;
  const PremiumPaywallScreen({super.key, this.showSkip = true, this.forceShowPlans = false});

  @override
  ConsumerState<PremiumPaywallScreen> createState() => _PremiumPaywallScreenState();
}

class _PremiumPaywallScreenState extends ConsumerState<PremiumPaywallScreen> {
  // Which paid-plan duration is selected — 30 (monthly) or 90 (quarterly).
  // Only meaningful once the plan list has loaded; _PlanSelector defaults
  // it to the shortest paid plan the first time it sees the real list.
  int _selectedDurationDays = 30;

  Future<void> _finishOnboardingWithoutPurchase() async {
    await ref.read(profileCreationControllerProvider.notifier).submit();
    if (mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(premiumPlansProvider);
    final mySubscription = ref.watch(mySubscriptionProvider);
    final isPremium = mySubscription.valueOrNull?.isPremium ?? false;
    final showMembershipScreen = isPremium && !widget.forceShowPlans;

    return Scaffold(
      appBar: AppBar(
        title: Text(showMembershipScreen ? 'Premium Membership' : 'Upgrade to Premium'),
        actions: [
          if (showMembershipScreen)
            IconButton(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'Help',
              onPressed: () => context.push(AppRoutes.aiAssistant),
            ),
          if (widget.showSkip && !showMembershipScreen)
            TextButton(
              onPressed: _finishOnboardingWithoutPurchase,
              child: const Text('SKIP'),
            ),
        ],
      ),
      body: mySubscription.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Best-effort — if the status check itself fails, fall through to
        // the regular plan picker rather than blocking the whole screen.
        error: (e, st) => plans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorStateView(
            failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
            onRetry: () => ref.invalidate(premiumPlansProvider),
          ),
          data: (planList) => _PlanSelector(
            plans: planList,
            selectedDurationDays: _selectedDurationDays,
            onDurationChanged: (d) => setState(() => _selectedDurationDays = d),
          ),
        ),
        data: (sub) {
          if (sub.isPremium && !widget.forceShowPlans) {
            return PremiumMembershipScreen(subscription: sub);
          }
          return plans.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorStateView(
              failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
              onRetry: () => ref.invalidate(premiumPlansProvider),
            ),
            data: (planList) {
              // The caller's current tier rank — 0 (free) unless their
              // plan_code resolves to a real plan in the list. Drives the
              // upgrade-only filter below: only plans ranked *above* this
              // are ever selectable here (mirrors the same rule enforced
              // server-side in payments.Service.Checkout).
              var currentTierRank = 0;
              for (final p in planList) {
                if (p.code == sub.planCode) {
                  currentTierRank = p.tierRank;
                  break;
                }
              }
              return _PlanSelector(
                plans: planList,
                selectedDurationDays: _selectedDurationDays,
                onDurationChanged: (d) => setState(() => _selectedDurationDays = d),
                currentTierRank: currentTierRank,
              );
            },
          );
        },
      ),
    );
  }
}

/// The free plan plus every paid-plan duration *above* the caller's
/// current tier, laid out as: header, a Monthly/Quarterly/Yearly duration
/// switch (only shown when more than one is selectable), a Basic card,
/// the selected paid plan — each duration is its own metal tier (Platinum
/// for monthly, Silver for quarterly, Gold for yearly, see [PlanTier]) —
/// Continue, and a footer line.
///
/// Upgrade-only by design: a plan ranked at or below [currentTierRank]
/// never appears here, matching the same rule enforced server-side in
/// payments.Service.Checkout — the filtering here is for a good UI, not
/// the actual gate. Someone already on the top tier sees no plans and a
/// "you're on our best plan" message instead of an empty list.
class _PlanSelector extends StatelessWidget {
  final List<SubscriptionPlan> plans;
  final int selectedDurationDays;
  final ValueChanged<int> onDurationChanged;

  /// The caller's current plan's tier rank — 0 for a free/new member.
  /// Only plans ranked strictly higher are ever shown or selectable.
  final int currentTierRank;

  const _PlanSelector({
    required this.plans,
    required this.selectedDurationDays,
    required this.onDurationChanged,
    this.currentTierRank = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return Center(
        child: Text('No plans are available right now.',
            style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
      );
    }

    SubscriptionPlan? freePlan;
    for (final p in plans) {
      if (p.priceINR == 0) {
        freePlan = p;
        break;
      }
    }
    final paidPlans = plans
        .where((p) => p.priceINR > 0 && p.tierRank > currentTierRank)
        .toList()
      ..sort((a, b) => a.durationDays.compareTo(b.durationDays));

    if (paidPlans.isEmpty) {
      return currentTierRank > 0
          ? const _TopTierMessage()
          : Center(
              child: Text('No plans are available right now.',
                  style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
            );
    }
    final selectedPlan = paidPlans.firstWhere(
      (p) => p.durationDays == selectedDurationDays,
      orElse: () => paidPlans.first,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: context.colors.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.workspace_premium_rounded, color: context.colors.accent, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Vivah Premium', style: context.textStyles.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Unlock chat, unlimited interests and contact details to connect with your matches.',
            style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (paidPlans.length > 1)
            _DurationSwitch(
              plans: paidPlans,
              selectedDurationDays: selectedPlan.durationDays,
              onChanged: onDurationChanged,
            ),
          if (paidPlans.length > 1) const SizedBox(height: AppSpacing.lg),
          if (freePlan != null && currentTierRank == 0) _BasicTierCard(plan: freePlan),
          if (freePlan != null && currentTierRank == 0) const SizedBox(height: AppSpacing.md),
          _PremiumTierCard(plan: selectedPlan),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Continue with Premium',
            onPressed: () => context.push(AppRoutes.orderSummary, extra: selectedPlan),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text('Secure payment via Razorpay · No auto-renewal',
                style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
          ),
        ],
      ),
    );
  }
}

/// Monthly / Quarterly (etc.) segmented switch. The non-monthly option's
/// label carries a "Save N%" hint computed from the real prices — never a
/// hardcoded marketing number — comparing its per-month cost against
/// paying for the shortest duration repeatedly.
class _DurationSwitch extends StatelessWidget {
  final List<SubscriptionPlan> plans;
  final int selectedDurationDays;
  final ValueChanged<int> onChanged;

  const _DurationSwitch({
    required this.plans,
    required this.selectedDurationDays,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final shortest = plans.first;
    final shortestMonthlyRate = shortest.priceINR / (shortest.durationDays / 30);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        children: plans.map((plan) {
          final selected = plan.durationDays == selectedDurationDays;
          final monthlyRate = plan.priceINR / (plan.durationDays / 30);
          final savingsPct =
              plan == shortest ? null : (100 - (monthlyRate / shortestMonthlyRate * 100)).round();

          final tier = PlanTier.forDuration(plan.durationDays);

          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(plan.durationDays),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? tier.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  savingsPct != null && savingsPct > 0
                      ? '${plan.durationLabel} · Save $savingsPct%'
                      : plan.durationLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodyMedium?.copyWith(
                    color: selected ? Colors.white : context.colors.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Shown instead of the plan picker when the caller is already on the
/// highest available tier (Gold/Yearly) — no empty list, no error, just a
/// clear "there's nothing higher to move to" message.
class _TopTierMessage extends StatelessWidget {
  const _TopTierMessage();

  @override
  Widget build(BuildContext context) {
    final gold = PlanTier.gold;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: gold.tint, shape: BoxShape.circle),
              child: Icon(Icons.workspace_premium_rounded, color: gold.accent, size: 32),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text("You're on our best plan",
                style: context.textStyles.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "You're already a Gold (Yearly) member — there's no higher plan to move to.",
              style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BasicTierCard extends StatelessWidget {
  final SubscriptionPlan plan;
  const _BasicTierCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Basic', style: context.textStyles.titleMedium),
          const SizedBox(height: 2),
          Text('Free · your current plan',
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
          const SizedBox(height: AppSpacing.sm),
          const _Feature(label: 'Browse & shortlist profiles', included: true),
          const _Feature(label: 'Standard visibility', included: true),
        ],
      ),
    );
  }
}

class _PremiumTierCard extends StatelessWidget {
  final SubscriptionPlan plan;
  const _PremiumTierCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final perMonth = (plan.priceINR / (plan.durationDays / 30)).round();
    final tier = PlanTier.forDuration(plan.durationDays);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: tier.tint,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: tier.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: tier.accent,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(tier.label.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(plan.name, style: context.textStyles.titleMedium)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹$perMonth/mo',
                      style: context.textStyles.titleMedium
                          ?.copyWith(color: tier.accent, fontWeight: FontWeight.w700)),
                  if (plan.durationDays > 30)
                    Text('Billed ₹${plan.priceINR} every ${plan.durationLabel}',
                        style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Feature(label: 'Chat with your matches', included: plan.hasChat),
          _Feature(label: 'Unlimited interests', included: plan.hasUnlimitedInterests),
          _Feature(label: 'View contact details', included: plan.hasViewContact),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final String label;
  final bool included;
  const _Feature({required this.label, required this.included});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            included ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline_rounded,
            size: 18,
            color: included ? context.colors.success : context.colors.muted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: context.textStyles.bodyMedium?.copyWith(
                color: included ? context.colors.ink : context.colors.muted,
                decoration: included ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
