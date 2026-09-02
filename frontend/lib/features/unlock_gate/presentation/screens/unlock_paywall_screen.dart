import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../premium/data/razorpay_service.dart';
import '../../data/api_unlock_repository.dart';

/// The ₹1 "pay to continue" gate — shown once the free demo swipe deck
/// (DemoSwipeDeckScreen) is exhausted, or whenever a real feature call
/// comes back 402 unlock_required (see api_error_mapper.dart /
/// AppFailureType.unlockRequired) for an already-onboarded-but-unpaid
/// account. Reuses the same RazorpayService / checkout-then-verify flow
/// features/premium/presentation/screens/order_summary_screen.dart uses,
/// just pointed at /unlock/* instead of /payments/*. Completely separate
/// from — and does not touch — the plan-based Premium subscription flow.
class UnlockPaywallScreen extends ConsumerStatefulWidget {
  const UnlockPaywallScreen({super.key});

  @override
  ConsumerState<UnlockPaywallScreen> createState() => _UnlockPaywallScreenState();
}

class _UnlockPaywallScreenState extends ConsumerState<UnlockPaywallScreen>
    with SingleTickerProviderStateMixin {
  bool _processing = false;
  final _razorpay = RazorpayService();

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _razorpay.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() => _processing = true);

    final checkoutResult = await ref.read(unlockRepositoryProvider).checkout();
    final checkout = checkoutResult.when(success: (c) => c, failure: (_) => null);
    if (checkout == null) {
      if (mounted) {
        setState(() => _processing = false);
        final failure = checkoutResult.when(success: (_) => null, failure: (f) => f);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure?.message ?? 'Could not start checkout.')));
      }
      return;
    }

    if (checkout.unlocked) {
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    final user = ref.read(authControllerProvider).user;
    final contact = user?.phoneOrEmail;
    final looksLikeEmail = contact?.contains('@') ?? false;

    try {
      final result = await _razorpay.open(
        orderId: checkout.orderId!,
        keyId: checkout.razorpayKeyId!,
        amountInPaise: checkout.amountPaise!,
        description: 'Unlock full access',
        contactName: 'Member',
        contactEmail: looksLikeEmail ? contact : null,
        contactPhone: looksLikeEmail ? null : contact,
      );

      final verifyResult = await ref.read(unlockRepositoryProvider).verify(
            orderId: result.orderId,
            paymentId: result.paymentId,
            signature: result.signature,
          );
      final unlocked = verifyResult.when(success: (v) => v, failure: (_) => false);
      if (!unlocked) {
        if (mounted) {
          setState(() => _processing = false);
          final failure = verifyResult.when(success: (_) => null, failure: (f) => f);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(failure?.message ?? 'Payment succeeded but verification failed.')));
        }
        return;
      }

      if (mounted) context.go(AppRoutes.home);
    } on PaymentFailure catch (f) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment failed. Please try again.')));
      }
    }
  }

  static const _features = [
    (Icons.favorite_rounded, 'Unlimited real matches & search filters'),
    (Icons.chat_bubble_rounded, 'Chat with your connections'),
    (Icons.call_rounded, 'Voice & video calls'),
    (Icons.send_rounded, 'Send unlimited interests'),
    (Icons.visibility_rounded, 'See who visited your profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final reveal = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Unlock Vivah', style: TextStyle(color: Colors.white)),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.premiumGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
            child: FadeTransition(
              opacity: reveal,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                    .animate(reveal),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    // A soft glow behind the badge reads as "premium" far
                    // more than a flat icon circle — cheap to do with a
                    // blurred BoxShadow, no extra assets needed.
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFE1B8), Color(0xFFE9A178)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE9A178).withValues(alpha: 0.55),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: Color(0xFF8B1E4A), size: 48),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Liked what you saw?',
                      style: context.textStyles.displaySmall
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Unlock everything Vivah has to offer — for a one-time ₹1.\nNo subscription, no recurring charges.',
                      style: context.textStyles.bodyLarge
                          ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Glassmorphism feature card — this is what makes the
                    // gate feel like a premium unlock rather than a bare
                    // paywall: every feature the user is about to get is
                    // spelled out, each with its own icon.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (icon, label) in _features)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(icon, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: context.textStyles.bodyMedium
                                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  const Icon(Icons.check_circle_rounded,
                                      color: Color(0xFFFFE1B8), size: 20),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Price badge — one honest number, no fabricated
                    // "was ₹X" strike-through (there's no real discount
                    // happening here, so faking one would just be a lie).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('₹1',
                              style: context.textStyles.displaySmall?.copyWith(
                                  color: const Color(0xFF8B1E4A), fontWeight: FontWeight.w800)),
                          const SizedBox(width: AppSpacing.sm),
                          Text('one-time',
                              style: context.textStyles.bodyMedium
                                  ?.copyWith(color: context.colors.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: 'Pay ₹1 to continue',
                        loading: _processing,
                        onPressed: _pay,
                        trailingIcon: Icons.arrow_forward_rounded,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 14, color: Colors.white.withValues(alpha: 0.75)),
                        const SizedBox(width: 6),
                        Text('Secure payment via Razorpay · One-time only',
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
