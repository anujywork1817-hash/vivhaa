import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../controllers/auth_controller.dart';

enum _AuthMode { signUp, logIn }

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// First screen after splash: an email+password sign-up-or-login form
/// (plus Google) — the gate every session starts from before any profile
/// questions.
class AuthChoiceScreen extends ConsumerStatefulWidget {
  const AuthChoiceScreen({super.key});

  @override
  ConsumerState<AuthChoiceScreen> createState() => _AuthChoiceScreenState();
}

class _AuthChoiceScreenState extends ConsumerState<AuthChoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.signUp;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _routeAfterAuth() async {
    // Returning users (an existing backend profile) skip onboarding
    // entirely; new users go through it as usual.
    final hasProfile = await ref.read(profileCreationControllerProvider.notifier).loadExisting();
    if (!mounted) return;
    context.go(hasProfile ? AppRoutes.home : AppRoutes.profileFor);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final notifier = ref.read(authControllerProvider.notifier);

    final ok = _mode == _AuthMode.signUp
        ? await notifier.signup(email, password)
        : await notifier.login(email, password);
    if (!mounted) return;

    if (ok) {
      await _routeAfterAuth();
      return;
    }

    final failure = ref.read(authControllerProvider).failure;
    if (failure == null) return;

    if (_mode == _AuthMode.signUp && failure.code == 'already_registered') {
      setState(() => _mode = _AuthMode.logIn);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('You already have an account with this email — log in instead.'),
        ));
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.message)));
  }

  Future<void> _signInWithGoogle() async {
    final result = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;

    switch (result) {
      case GoogleSignInResult.signedIn:
        await _routeAfterAuth();
      case GoogleSignInResult.otpRequired:
        // A first-time signup via the legacy passwordless path:
        // AuthController already sent the OTP and set pendingContact to
        // the Google account's email, so the OTP screen's existing
        // verifyOtp() call needs nothing Google-specific — this proceeds
        // exactly like any other signup from here.
        context.push(AppRoutes.otp);
      case GoogleSignInResult.failed:
        final failure = ref.read(authControllerProvider).failure;
        if (failure != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(failure.message)));
        }
      case GoogleSignInResult.cancelled:
      // No error to show — the user closed the account picker.
    }
  }

  void _openForgotPassword() {
    context.push(AppRoutes.forgotPassword, extra: _emailController.text.trim());
  }

  String? _validateEmail(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Enter your email address';
    if (!_emailPattern.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Enter your password';
    if (_mode == _AuthMode.signUp && value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xl),
            child: Column(
              children: [
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
                const SizedBox(height: AppSpacing.xxl),
                _ModeToggle(
                  mode: _mode,
                  onChanged: isLoading
                      ? null
                      : (mode) => setState(() => _mode = mode),
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          validator: _validateEmail,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: [
                            _mode == _AuthMode.signUp
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          validator: _validatePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: _mode == _AuthMode.signUp ? 'At least 8 characters' : null,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),
                        if (_mode == _AuthMode.logIn) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: isLoading ? null : _openForgotPassword,
                              child: const Text('Forgot password?'),
                            ),
                          ),
                        ] else
                          const SizedBox(height: AppSpacing.sm),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _submit,
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.2, color: Colors.white),
                                  )
                                : Text(_mode == _AuthMode.signUp ? 'Sign Up' : 'Log In'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.4))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text('or',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                    ),
                    Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.4))),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _ChoicePill(
                  icon: Icons.g_mobiledata_rounded,
                  label: 'Continue with Google',
                  loading: isLoading,
                  onTap: isLoading ? null : _signInWithGoogle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _AuthMode mode;
  final ValueChanged<_AuthMode>? onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(context, 'Sign Up', _AuthMode.signUp)),
          Expanded(child: _segment(context, 'Log In', _AuthMode.logIn)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, _AuthMode value) {
    final selected = mode == value;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.94) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
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
              mainAxisAlignment: MainAxisAlignment.center,
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
