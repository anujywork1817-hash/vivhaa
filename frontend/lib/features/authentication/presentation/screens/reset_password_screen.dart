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

/// How long the Resend button stays disabled after a tap — mirrors
/// OtpScreen's client-side spam-prevention cooldown ahead of the backend's
/// own per-identifier rate limiting.
const _resendCooldown = Duration(seconds: 45);

const _devOtpBannerDuration = Duration(seconds: 8);

/// Step 2 of the forgot-password flow: the 6-digit code sent to the email
/// from ForgotPasswordScreen, plus the new password — submitting calls
/// POST /auth/reset-password and logs the account straight in on success.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _code = '';
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  Timer? _cooldownTimer;
  int _cooldownSecondsLeft = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowDevOtpBanner());
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _maybeShowDevOtpBanner([String? code]) {
    final devOtp = code ?? ref.read(authControllerProvider).lastDevOtp;
    if (devOtp == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('Dev code: $devOtp'), duration: _devOtpBannerDuration));
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
    final contact = ref.read(authControllerProvider).pendingContact;
    if (contact == null) return;
    final ok =
        await ref.read(authControllerProvider.notifier).forgotPassword(contact);
    if (!mounted) return;
    if (ok) {
      _startResendCooldown();
      final devOtp = ref.read(authControllerProvider).lastDevOtp;
      if (devOtp != null) {
        _maybeShowDevOtpBanner(devOtp);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('Code resent')));
      }
    } else {
      final failure = ref.read(authControllerProvider).failure;
      if (failure != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              duration: const Duration(seconds: 3),
              content: Text(failure.message)));
      }
    }
  }

  String? _validateNewPassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Enter a new password';
    if (value.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _validateConfirmPassword(String? v) {
    if (v != _newPasswordController.text) return "Passwords don't match";
    return null;
  }

  Future<void> _submit() async {
    if (_code.length != 6) return;
    if (!_formKey.currentState!.validate()) return;

    final ok = await ref
        .read(authControllerProvider.notifier)
        .resetPassword(_code, _newPasswordController.text);
    if (!ok || !mounted) return;

    final hasProfile = await ref
        .read(profileCreationControllerProvider.notifier)
        .loadExisting();
    if (!mounted) return;
    context.go(hasProfile ? AppRoutes.home : AppRoutes.profileFor);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final canResend = _cooldownSecondsLeft <= 0;
    final canSubmit = _code.length == 6;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reset your password',
                    style: context.textStyles.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Enter the 6-digit code sent to ${authState.pendingContact ?? 'your email'}, then choose a new password.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.colors.muted),
                ),
                const SizedBox(height: AppSpacing.xxl),
                OtpInputField(
                    onCompleted: (code) => setState(() => _code = code)),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: canResend ? _resend : null,
                    child: Text(canResend
                        ? "Didn't get a code? Resend"
                        : 'Resend in ${_cooldownSecondsLeft}s'),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNew,
                  validator: _validateNewPassword,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    hintText: 'At least 8 characters',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  validator: _validateConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),
                if (authState.failure != null) ...[
                  const SizedBox(height: 14),
                  Text(authState.failure!.message,
                      style: TextStyle(
                          color: context.colors.danger, fontSize: 13)),
                ],
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Reset password',
                  onPressed: canSubmit ? _submit : null,
                  loading: authState.isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
