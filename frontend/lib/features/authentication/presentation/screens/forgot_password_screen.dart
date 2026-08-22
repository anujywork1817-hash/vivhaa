import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../controllers/auth_controller.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Step 1 of the forgot-password flow: collect the email, then move on
/// unconditionally — the backend always returns 200 here regardless of
/// whether the account exists, specifically to avoid leaking which emails
/// are registered, so this screen never shows a "no such account" error.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .forgotPassword(_emailController.text.trim());
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('If that account exists, a code has been sent to it.'),
        ));
      context.push(AppRoutes.resetPassword);
    }
    // On a genuine network/server failure (not "account doesn't exist" —
    // the backend never says that), authState.failure is shown below.
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
                Text('Forgot password?',
                    style: context.textStyles.displaySmall),
                const SizedBox(height: 6),
                Text(
                  "Enter your account's email and we'll send you a code to reset your password.",
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.colors.muted),
                ),
                const SizedBox(height: AppSpacing.xxl),
                AppTextField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Enter your email address';
                    if (!_emailPattern.hasMatch(value))
                      return 'Enter a valid email address';
                    return null;
                  },
                ),
                if (authState.failure != null) ...[
                  const SizedBox(height: 10),
                  Text(authState.failure!.message,
                      style: TextStyle(
                          color: context.colors.danger, fontSize: 13)),
                ],
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Send code',
                  onPressed: _continue,
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
