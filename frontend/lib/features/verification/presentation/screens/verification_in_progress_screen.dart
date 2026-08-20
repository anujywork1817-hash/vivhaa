import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';

/// Note: this screen intentionally does not mark the profile as
/// selfie-verified — that flag only becomes true once an admin actually
/// approves the submission (see [ApiVerificationRepository]); onboarding
/// just moves on while review happens in the background.
class VerificationInProgressScreen extends StatefulWidget {
  const VerificationInProgressScreen({super.key});

  @override
  State<VerificationInProgressScreen> createState() =>
      _VerificationInProgressScreenState();
}

class _VerificationInProgressScreenState extends State<VerificationInProgressScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) context.go(AppRoutes.hobbies);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: context.colors.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.timer_outlined, color: context.colors.accent, size: 30),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Profile Verification is in progress',
                  textAlign: TextAlign.center, style: context.textStyles.titleMedium),
              const SizedBox(height: 6),
              Text("We'll notify you once your Profile is verified",
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
              const SizedBox(height: AppSpacing.xl),
              Text.rich(
                TextSpan(
                  text: 'Need help? ',
                  style: context.textStyles.bodySmall,
                  children: [
                    TextSpan(
                      text: 'Visit Help and Support',
                      style: TextStyle(color: context.colors.accent, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
