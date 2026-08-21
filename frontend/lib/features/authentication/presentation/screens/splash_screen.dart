import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';

/// Logo-only splash — also where an existing session gets picked back up:
/// if a stored access token is still good (ApiClient transparently
/// refreshes it if merely expired), skip straight past the auth gate
/// instead of forcing sign-in on every app restart.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
    _resume();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    final minSplash = Future.delayed(const Duration(milliseconds: 1400));

    // BUG-F01 / BUG-M01: both readAccessToken() and loadExisting() were
    // unguarded — a flutter_secure_storage failure (e.g. BAD_DECRYPT after
    // an Android backup/restore corrupts the encrypted prefs file) threw
    // out of this method with nothing left to call context.go(...), so the
    // app hung on the splash screen forever with no way forward. Any
    // failure here now falls back to the same safe restart point a
    // logged-out user already lands on.
    String destination = AppRoutes.authChoice;
    try {
      final token = await ref.read(secureStorageServiceProvider).readAccessToken();
      if (token != null) {
        // A valid-or-refreshable token plus an existing profile means a
        // returning, fully set-up member — send them straight in. Any
        // other outcome (no session, no profile yet) falls back to the
        // auth gate, which is always a safe restart point.
        final hasProfile = await ref.read(profileCreationControllerProvider.notifier).loadExisting();
        if (hasProfile) destination = AppRoutes.home;
      }
    } catch (e) {
      debugPrint('SplashScreen._resume: session resume failed, falling back to auth gate — $e');
    }

    await minSplash;
    if (mounted) context.go(destination);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Vivah',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 42,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
