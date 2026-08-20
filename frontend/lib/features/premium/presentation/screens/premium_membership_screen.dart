import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/my_subscription.dart';
import '../../../../shared/models/payment_record.dart';
import '../../../../shared/models/profile.dart';
import '../../../../shared/models/subscription_plan.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../controllers/premium_controller.dart';
import '../plan_tier.dart';

/// The "you already have Premium" view — real member ID, join date, plan,
/// billing date/amount and payment history, all bound to actual API
/// responses. Rendered by [PremiumPaywallScreen] once it's confirmed
/// [subscription] is a genuinely active, non-expired paid plan (the
/// backend's own `/subscriptions/me` query already excludes expired rows,
/// falling back to the free plan — so `subscription.isPremium` here is
/// never a stale/optimistic flag).
class PremiumMembershipScreen extends ConsumerWidget {
  final MySubscription subscription;
  const PremiumMembershipScreen({super.key, required this.subscription});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(premiumPlansProvider);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    return plansAsync.when(
      loading: () => const _MembershipSkeleton(),
      error: (e, st) => ErrorStateView(
        failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
        onRetry: () => ref.invalidate(premiumPlansProvider),
      ),
      data: (plans) {
        SubscriptionPlan? plan;
        for (final p in plans) {
          if (p.code == subscription.planCode) {
            plan = p;
            break;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MemberHeader(profile: draft),
              const SizedBox(height: AppSpacing.lg),
              _ActivePlanCard(subscription: subscription, plan: plan),
              const SizedBox(height: AppSpacing.md),
              const _PaymentMethodCard(),
              const SizedBox(height: AppSpacing.lg),
              Text('Billing History', style: context.textStyles.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              const _BillingHistoryList(),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      context.push(AppRoutes.premiumPaywall, extra: true),
                  child: const Text('Change Plan'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberHeader extends StatelessWidget {
  final Profile profile;
  const _MemberHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final name = profile.fullName ?? 'Your profile';
    final memberId = profile.profileCode.isNotEmpty ? profile.profileCode : '—';
    final joinedAt = profile.createdAt;
    final verified = profile.selfieVerified;

    return Row(
      children: [
        ProfileAvatar(name: name, size: 56, photoUrl: profile.profilePhotoUrl),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(name,
                        style: context.textStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded, size: 16, color: context.colors.accent),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text('Member ID: $memberId',
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (joinedAt != null)
                Text('Joined on ${_formatDate(joinedAt)}',
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// The active-plan card: plan name, status pill, next billing date, and
/// the actual amount charged for this plan — pulled from the most recent
/// *paid* history row for this plan code when available (accounts for any
/// coupon discount actually applied), falling back to the plan's list
/// price only if no matching payment record is found.
class _ActivePlanCard extends ConsumerWidget {
  final MySubscription subscription;
  final SubscriptionPlan? plan;
  const _ActivePlanCard({required this.subscription, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(paymentHistoryProvider);
    final endsAt = subscription.endsAt;

    int? amountPaid;
    final history = historyAsync.valueOrNull;
    if (history != null) {
      for (final p in history) {
        if (p.planCode == subscription.planCode && p.isPaid) {
          amountPaid = p.amountINR - p.discountINR;
          break;
        }
      }
    }
    amountPaid ??= plan?.priceINR;

    final statusLabel = subscription.status == 'active' ? 'Active' : subscription.status;
    final statusColor =
        subscription.status == 'active' ? context.colors.success : context.colors.muted;

    // Monthly = Platinum, Quarterly = Silver, Yearly = Gold (see PlanTier).
    // Falls back to the app's rose accent only in the unlikely event the
    // plan list hasn't resolved this subscription's plan code to an
    // actual plan yet.
    final tier = plan != null ? PlanTier.forDuration(plan!.durationDays) : null;
    final accentColor = tier?.accent ?? context.colors.accent;
    final tintColor = tier?.tint ?? context.colors.accentSoft;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tintColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: accentColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan?.name ?? subscription.planCode,
                        style: context.textStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (tier != null)
                      Text('${tier.label} Member',
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: accentColor, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration:
                    BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(AppSpacing.radiusPill)),
                child: Text(statusLabel.toUpperCase(),
                    maxLines: 1,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          _InfoRow(
            label: 'Next Billing Date',
            value: endsAt != null ? _formatDate(endsAt) : '—',
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            label: 'Amount',
            value: amountPaid != null ? '₹$amountPaid' : '—',
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            label: 'Auto Renewal',
            // There is no recurring-billing concept on the backend — every
            // purchase is a one-time charge for a fixed duration, so this
            // reports that fact rather than a fake ON/OFF toggle.
            value: 'One-time · does not auto-renew',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
        const Spacer(),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// The backend never receives or stores card details — Razorpay's
/// checkout SDK collects them client-side per transaction — so there is
/// no masked card number to show and nothing to "change". This says so
/// plainly instead of fabricating a card.
class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.line),
      ),
      child: Row(
        children: [
          Icon(Icons.credit_card_rounded, color: context.colors.muted, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment Method', style: context.textStyles.titleSmall),
                const SizedBox(height: 2),
                Text('Not available · handled securely by Razorpay at checkout',
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingHistoryList extends ConsumerWidget {
  const _BillingHistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(paymentHistoryProvider);

    return historyAsync.when(
      loading: () => Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ShimmerBox(
                width: double.infinity, height: 64, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          ),
        ),
      ),
      error: (e, st) => ErrorStateView(
        failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
        onRetry: () => ref.invalidate(paymentHistoryProvider),
      ),
      data: (records) {
        if (records.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: context.colors.line),
            ),
            child: Center(
              child: Text('No payments yet',
                  style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
            ),
          );
        }
        return Column(
          children: [
            for (final record in records) ...[
              _BillingRow(record: record),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _BillingRow extends StatelessWidget {
  final PaymentRecord record;
  const _BillingRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final netAmount = record.amountINR - record.discountINR;
    final statusColor = switch (record.status) {
      'paid' => context.colors.success,
      'failed' => context.colors.danger,
      _ => context.colors.muted,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.planName.isNotEmpty ? record.planName : record.planCode,
                    style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_formatDate(record.paidAt ?? record.createdAt),
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹$netAmount',
                  style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(record.status,
                  style: context.textStyles.bodySmall?.copyWith(
                      color: statusColor, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MembershipSkeleton extends StatelessWidget {
  const _MembershipSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerBox(width: 56, height: 56, borderRadius: BorderRadius.circular(28)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 140, height: 18, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 8),
                    ShimmerBox(width: 100, height: 12, borderRadius: BorderRadius.circular(4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ShimmerBox(
              width: double.infinity, height: 180, borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
          const SizedBox(height: AppSpacing.md),
          ShimmerBox(
              width: double.infinity, height: 72, borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
          const SizedBox(height: AppSpacing.lg),
          ShimmerBox(width: 140, height: 20, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: AppSpacing.sm),
          ShimmerBox(
              width: double.infinity, height: 64, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          const SizedBox(height: AppSpacing.sm),
          ShimmerBox(
              width: double.infinity, height: 64, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        ],
      ),
    );
  }
}
