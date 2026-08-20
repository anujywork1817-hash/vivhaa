import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../buttons/primary_button.dart';

/// Shared shell for every step in the profile-creation flow: a progress
/// rail, step title/subtitle, scrollable form body, and a pinned continue
/// button. Keeps the 12 profile-creation screens from re-deriving layout.
class OnboardingStepScaffold extends StatelessWidget {
  final int stepIndex;
  final int stepCount;
  final String title;
  final String? subtitle;
  final Widget child;
  final String continueLabel;
  final VoidCallback? onContinue;
  final bool loading;
  final Widget? footer;
  final IconData? headerIcon;

  const OnboardingStepScaffold({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    required this.title,
    this.subtitle,
    required this.child,
    this.continueLabel = 'Continue',
    required this.onContinue,
    this.loading = false,
    this.footer,
    this.headerIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (headerIcon != null) ...[
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: context.colors.accentSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(headerIcon, size: 30, color: context.colors.accent),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    Text(title, style: context.textStyles.headlineMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(subtitle!,
                          style: context.textStyles.bodyMedium
                              ?.copyWith(color: context.colors.muted)),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                children: [
                  PrimaryButton(
                    label: continueLabel,
                    onPressed: onContinue,
                    loading: loading,
                    trailingIcon: Icons.arrow_forward_rounded,
                  ),
                  if (footer != null) ...[const SizedBox(height: 12), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
