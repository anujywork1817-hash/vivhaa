import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/profile_detail.dart';

/// Explains exactly what "verified" means for this member — shown when
/// the verification badge on the profile is tapped.
class VerificationInfoSheet extends StatelessWidget {
  final ProfileDetail detail;
  const VerificationInfoSheet({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.colors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.verified_rounded, color: context.colors.accent),
                const SizedBox(width: AppSpacing.sm),
                Text('Verification', style: context.textStyles.headlineSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'These checks help keep the community genuine. A verified badge means the checks below have passed.',
              style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Row(icon: Icons.badge_outlined, label: 'Government ID', verified: detail.idVerified),
            _Row(icon: Icons.phone_iphone_rounded, label: 'Phone number', verified: detail.phoneVerified),
            _Row(icon: Icons.photo_camera_outlined, label: 'Photo', verified: detail.photoVerified),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool verified;
  const _Row({required this.icon, required this.label, required this.verified});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: context.colors.muted, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: context.textStyles.bodyLarge)),
          Icon(
            verified ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            color: verified ? context.colors.success : context.colors.muted,
            size: 20,
          ),
        ],
      ),
    );
  }
}
