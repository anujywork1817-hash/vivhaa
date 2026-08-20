import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/api_verification_repository.dart';
import '../controllers/selfie_controller.dart';

class VerifyingScreen extends ConsumerStatefulWidget {
  const VerifyingScreen({super.key});

  @override
  ConsumerState<VerifyingScreen> createState() => _VerifyingScreenState();
}

class _VerifyingScreenState extends ConsumerState<VerifyingScreen> {
  @override
  void initState() {
    super.initState();
    _submit();
  }

  Future<void> _submit() async {
    final path = ref.read(selfiePathProvider);
    // Submission is best-effort and non-blocking: the backend review is
    // async either way, so a failed upload (e.g. offline, or a repeat
    // submission while one's already pending) shouldn't strand the user
    // mid-onboarding — it just means their verification wasn't recorded.
    if (path != null) {
      await ref.read(verificationRepositoryProvider).submitSelfie(path);
    }
    if (mounted) context.go(AppRoutes.verificationInProgress);
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
              CircularProgressIndicator(color: context.colors.accent),
              const SizedBox(height: AppSpacing.lg),
              Text('Hold tight! Your identity is being verified.',
                  textAlign: TextAlign.center, style: context.textStyles.titleMedium),
              const SizedBox(height: 6),
              Text('Please do not press Back or Exit.',
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
