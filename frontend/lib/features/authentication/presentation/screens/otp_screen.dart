import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/otp_input_field.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../controllers/auth_controller.dart';

/// How long the Resend button stays disabled after a tap — cheap
/// client-side spam prevention ahead of (not instead of) the backend's
/// own per-identifier rate limiting on POST /auth/request-otp.
const _resendCooldown = Duration(seconds: 45);

/// How long the dev-only OTP banner stays on screen. Only ever shown when
/// the backend actually returns a dev_otp (APP_ENV=dev) — see
/// AuthState.lastDevOtp's doc for why this can never appear in production.
const _devOtpBannerDuration = Duration(seconds: 8);

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _code = '';
  Timer? _cooldownTimer;
  int _cooldownSecondsLeft = 0;

  @override
  void initState() {
    super.initState();
    // The initial code was requested from the previous screen (before this
    // one even existed), so show its dev banner now rather than never.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowDevOtpBanner());
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _maybeShowDevOtpBanner([String? code]) {
    final devOtp = code ?? ref.read(authControllerProvider).lastDevOtp;
    if (devOtp == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Dev code: $devOtp'),
        duration: _devOtpBannerDuration,
      ));
  }

  void _startResendCooldown() {
    setState(() => _cooldownSecondsLeft = _resendCooldown.inSeconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownSecondsLeft--;
        if (_cooldownSecondsLeft <= 0) timer.cancel();
      });
    });
  }

  Future<void> _resend() async {
    final result = await ref.read(authControllerProvider.notifier).resendOtp();
    if (!mounted) return;

    result.when(
      success: (devOtp) {
        _startResendCooldown();
        if (devOtp != null) {
          _maybeShowDevOtpBanner(devOtp);
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Code resent')));
        }
      },
      failure: (f) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(f.message)));
      },
    );
  }

  Future<void> _verify() async {
    if (_code.length != 6) return;
    final ok = await ref.read(authControllerProvider.notifier).verifyOtp(_code);
    if (!ok || !mounted) return;

    // Returning users (an existing backend profile) skip onboarding
    // entirely; new users go through it as usual.
    final hasProfile = await ref.read(profileCreationControllerProvider.notifier).loadExisting();
    if (!mounted) return;
    context.go(hasProfile ? AppRoutes.home : AppRoutes.profileFor);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final canResend = _cooldownSecondsLeft <= 0;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verify your number', style: context.textStyles.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Enter the 6-digit code sent to ${authState.pendingContact ?? 'your number'}.',
                style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
              ),
              const SizedBox(height: AppSpacing.xxl),
              OtpInputField(onCompleted: (code) => setState(() => _code = code)),
              if (authState.failure != null) ...[
                const SizedBox(height: 14),
                Text(authState.failure!.message,
                    style: TextStyle(color: context.colors.danger, fontSize: 13)),
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Verify & Continue',
                onPressed: _code.length == 6 ? _verify : null,
                loading: authState.isLoading,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: canResend ? _resend : null,
                  child: Text(canResend
                      ? "Didn't get a code? Resend"
                      : 'Resend in ${_cooldownSecondsLeft}s'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
