import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../controllers/auth_controller.dart';
import 'login_screen.dart' show ContactMode;

/// First screen after splash: a sign-up-or-login gate, not a form —
/// mirrors how matrimonial apps front-load account creation before any
/// profile questions.
class AuthChoiceScreen extends ConsumerWidget {
  const AuthChoiceScreen({super.key});

  Future<void> _signInWithGoogle(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!context.mounted) return;
    if (ok) {
      // Returning users (an existing backend profile) skip onboarding
      // entirely; new users go through it as usual.
      final hasProfile = await ref.read(profileCreationControllerProvider.notifier).loadExisting();
      if (!context.mounted) return;
      context.go(hasProfile ? AppRoutes.home : AppRoutes.profileFor);
      return;
    }
    final failure = ref.read(authControllerProvider).failure;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message)),
      );
    }
    // A null failure means the user closed the account picker — no error.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xxxl, AppSpacing.xl, AppSpacing.xl),
            child: Column(
              children: [
                const Spacer(flex: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutBack,
                  builder: (context, t, child) => Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.scale(scale: 0.7 + (0.3 * t), child: child),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 8, bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
                      ),
                      const Text(
                        'Vivah',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'New here?',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _ChoicePill(
                  icon: Icons.mail_outline_rounded,
                  label: 'Sign Up with Email',
                  onTap: isLoading
                      ? null
                      : () => context.push(AppRoutes.login, extra: ContactMode.email),
                ),
                const SizedBox(height: AppSpacing.md),
                _ChoicePill(
                  icon: Icons.g_mobiledata_rounded,
                  label: 'Sign Up with Google',
                  loading: isLoading,
                  onTap: isLoading ? null : () => _signInWithGoogle(context, ref),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account?',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () => context.push(AppRoutes.login, extra: ContactMode.login),
                      child: const Text('Login',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _ChoicePill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                if (loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent),
                  )
                else
                  Icon(icon, color: AppColors.accent, size: 20),
                const SizedBox(width: 12),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 14.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
