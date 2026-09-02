import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
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

class _UnlockPaywallScreenState extends ConsumerState<UnlockPaywallScreen> {
  bool _processing = false;
  final _razorpay = RazorpayService();

  @override
  void dispose() {
    _razorpay.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock Vivah'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: context.colors.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.lock_open_rounded, color: context.colors.accent, size: 44),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Liked what you saw?', style: context.textStyles.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Pay a one-time ₹1 to unlock full access — real matches, search, interests, chat, calls and more. No subscription, just this once.',
                style: context.textStyles.bodyLarge?.copyWith(color: context.colors.muted),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              PrimaryButton(
                label: 'Pay ₹1 to continue',
                loading: _processing,
                onPressed: _pay,
                trailingIcon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Secure payment via Razorpay · One-time only',
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
