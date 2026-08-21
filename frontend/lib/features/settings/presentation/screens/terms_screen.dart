import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = [
    (
      'Acceptance of terms',
      'By creating a profile or otherwise using Vivah, you agree to these Terms & '
          'Conditions and our Privacy Policy. If you do not agree, please do not use the app.',
    ),
    (
      'Eligibility',
      'You must be at least 18 years old and legally eligible to marry under applicable '
          'law to create a profile on Vivah, whether for yourself or on behalf of a family '
          'member with their knowledge and consent.',
    ),
    (
      'Your profile & content',
      'You are responsible for the accuracy of the information and photos you provide. '
          'Profiles must represent a real person truthfully — impersonation, fake profiles, '
          'and misleading information are not allowed and may result in suspension.',
    ),
    (
      'Conduct',
      'Members agree not to harass, threaten, defraud, or solicit money from other '
          'members. Reported or blocked accounts may be reviewed and suspended at our '
          'discretion.',
    ),
    (
      'Subscriptions & payments',
      'Premium plans unlock additional features (chat, viewing contact details, and '
          'others as described at checkout) for the duration purchased. Payments are '
          'processed securely via Razorpay; subscriptions do not auto-renew unless '
          'stated otherwise at purchase.',
    ),
    (
      'Privacy',
      'We collect the information you provide to operate the matchmaking service — '
          'building your profile, showing you matches, and enabling communication with '
          'other members. We do not sell your personal data to third parties.',
    ),
    (
      'Account termination',
      'You may delete your account at any time from Account Settings. We may suspend '
          'or terminate accounts that violate these terms.',
    ),
    (
      'Changes to these terms',
      'We may update these terms from time to time. Continued use of the app after an '
          'update constitutes acceptance of the revised terms.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Last updated: January 2026',
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
          const SizedBox(height: AppSpacing.lg),
          for (final (title, body) in _sections) ...[
            Text(title, style: context.textStyles.titleSmall),
            const SizedBox(height: 6),
            Text(body, style: context.textStyles.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}
