import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../controllers/auth_controller.dart';

enum ContactMode { email, mobile, login }

class LoginScreen extends ConsumerStatefulWidget {
  final ContactMode mode;
  const LoginScreen({super.key, this.mode = ContactMode.login});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _contactController;

  bool get _isMobile => widget.mode == ContactMode.mobile;

  @override
  void initState() {
    super.initState();
    _contactController = TextEditingController(text: _isMobile ? '+91 ' : '');
  }

  @override
  void dispose() {
    _contactController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
        ContactMode.email => 'Sign up with email',
        ContactMode.mobile => 'Sign up with mobile',
        ContactMode.login => 'Welcome back',
      };

  String get _subtitle => switch (widget.mode) {
        ContactMode.email => 'Create a free profile using your email address.',
        ContactMode.mobile => 'Create a free profile using your mobile number.',
        ContactMode.login => 'Sign in to continue where you left off.',
      };

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authControllerProvider.notifier).requestOtp(_contactController.text);
    if (ok && mounted) context.push(AppRoutes.otp);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: context.textStyles.displaySmall),
                const SizedBox(height: 6),
                Text(_subtitle,
                    style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
                const SizedBox(height: AppSpacing.xxl),
                AppTextField(
                  label: _isMobile ? 'Mobile number' : 'Email or mobile number',
                  hint: _isMobile ? '+91 98765 43210' : 'you@example.com',
                  controller: _contactController,
                  keyboardType:
                      _isMobile ? TextInputType.phone : TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || v.trim().length < 6) ? 'Enter a valid number or email' : null,
                ),
                if (authState.failure != null) ...[
                  const SizedBox(height: 10),
                  Text(authState.failure!.message,
                      style: TextStyle(color: context.colors.danger, fontSize: 13)),
                ],
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: widget.mode == ContactMode.login ? 'Login' : 'Continue',
                  onPressed: _continue,
                  loading: authState.isLoading,
                ),
                const Spacer(),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'By continuing you agree to our ',
                      style: context.textStyles.bodySmall,
                      children: const [
                        TextSpan(text: 'Terms', style: TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: ' and '),
                        TextSpan(text: 'Privacy Policy', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
