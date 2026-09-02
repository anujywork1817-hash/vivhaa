import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../controllers/profile_creation_controller.dart';

class WelcomePendingScreen extends ConsumerWidget {
  const WelcomePendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final profileFor = draft.profileFor ?? ProfileFor.myself;
    final isMyself = profileFor == ProfileFor.myself;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  gradient: AppColors.heroGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                isMyself
                    ? 'Welcome, ${draft.fullName?.split(' ').first ?? 'there'}!'
                    : 'All set!',
                style: context.textStyles.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '${profileFor.possessiveTitle} profile has been submitted and is under review. '
                'This usually takes under 24 hours — we\'ll notify you the moment it\'s live.',
                style: context.textStyles.bodyLarge?.copyWith(color: context.colors.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.accentSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_user_rounded, color: context.colors.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Verification status: Pending review',
                        style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              PrimaryButton(
                label: 'Go to my dashboard',
                // "Hook then pay ₹1" gate: every new user sees the free
                // 10+10 demo swipe deck first (DemoSwipeDeckScreen), which
                // hands off to the ₹1 unlock paywall once exhausted —
                // never straight to home from here.
                onPressed: () => context.go(AppRoutes.demoSwipeDeck),
                trailingIcon: Icons.arrow_forward_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
