import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/subscription_plan.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../../data/api_payments_repository.dart';
import '../../data/razorpay_service.dart';
import '../controllers/premium_controller.dart';

class OrderSummaryScreen extends ConsumerStatefulWidget {
  final SubscriptionPlan plan;
  const OrderSummaryScreen({super.key, required this.plan});

  @override
  ConsumerState<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends ConsumerState<OrderSummaryScreen> {
  final _couponController = TextEditingController();
  bool _processing = false;
  final _razorpay = RazorpayService();

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    setState(() => _processing = true);

    final draft = ref.read(profileCreationControllerProvider).draft;
    final user = ref.read(authControllerProvider).user;
    final contact = user?.phoneOrEmail;
    final looksLikeEmail = contact?.contains('@') ?? false;
    final coupon = _couponController.text.trim();

    // 1. Ask the backend to create a real Razorpay order — the amount
    //    actually charged (after any coupon discount) is decided there,
    //    never computed on the client.
    final checkoutResult = await ref
        .read(paymentsRepositoryProvider)
        .checkout(widget.plan.code, couponCode: coupon.isEmpty ? null : coupon);

    final checkout = checkoutResult.when(success: (c) => c, failure: (f) => null);
    if (checkout == null) {
      if (mounted) {
        setState(() => _processing = false);
        final failure = checkoutResult.when(success: (_) => null, failure: (f) => f);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure?.message ?? 'Could not start checkout.')));
      }
      return;
    }

    try {
      // 2. Open the real Razorpay checkout against that order.
      final result = await _razorpay.open(
        orderId: checkout.orderId,
        keyId: checkout.razorpayKeyId,
        amountInPaise: checkout.amountPaise,
        description: widget.plan.name,
        contactName: draft.fullName ?? 'Member',
        contactEmail: looksLikeEmail ? contact : null,
        contactPhone: looksLikeEmail ? null : contact,
      );

      // 3. Verify the signature server-side and activate the subscription.
      final verifyResult = await ref.read(paymentsRepositoryProvider).verify(
            orderId: result.orderId,
            paymentId: result.paymentId,
            signature: result.signature,
          );
      final verified = verifyResult.when(success: (v) => v, failure: (f) => null);
      if (verified == null) {
        if (mounted) {
          setState(() => _processing = false);
          final failure = verifyResult.when(success: (_) => null, failure: (f) => f);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(failure?.message ?? 'Payment succeeded but verification failed.')));
        }
        return;
      }

      ref.invalidate(mySubscriptionProvider);
      await ref.read(profileCreationControllerProvider.notifier).submit();
      if (mounted) context.go(AppRoutes.home);
    } on PaymentFailure catch (f) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Payment failed. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Order Summary')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_rounded, color: context.colors.success, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text('Secure checkout via Razorpay',
                            style: context.textStyles.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xxl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(plan.name,
                            style: context.textStyles.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('₹${plan.priceINR}',
                          style: context.textStyles.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  Text('(${plan.durationLabel})',
                      style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Coupon code (optional)', style: context.textStyles.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _couponController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter coupon code',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'The final amount (including any coupon discount) is confirmed by the server '
                    'when you tap Proceed, right before checkout opens.',
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: PrimaryButton(label: 'Proceed', loading: _processing, onPressed: _proceed),
          ),
        ],
      ),
    );
  }
}
