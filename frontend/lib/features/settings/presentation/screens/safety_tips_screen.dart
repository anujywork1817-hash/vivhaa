import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';

const _tips = [
  (
    icon: Icons.videocam_outlined,
    title: 'Video chat before meeting',
    body: 'Talk over video call a few times before agreeing to meet in person.',
  ),
  (
    icon: Icons.groups_outlined,
    title: 'Meet in a public place',
    body: 'For your first few meetings, choose a public place and tell a friend or family member where you\'re going.',
  ),
  (
    icon: Icons.currency_rupee_rounded,
    title: 'Never send money',
    body: 'Vivah will never ask you to send money to a match. Be wary of anyone who does, especially early on.',
  ),
  (
    icon: Icons.lock_outline_rounded,
    title: 'Protect personal information',
    body: 'Avoid sharing your home address, bank details, or ID numbers until you\'ve built real trust.',
  ),
  (
    icon: Icons.flag_outlined,
    title: 'Report suspicious behavior',
    body: 'If a profile feels off — fake photos, asking for money, refusing video calls — report or block them.',
  ),
];

/// Static safety guidance — no backend needed, just honest content
/// instead of a dead menu button.
class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Be Safe Online')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _tips.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          final tip = _tips[i];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: context.colors.accentSoft, shape: BoxShape.circle),
                child: Icon(tip.icon, color: context.colors.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tip.title, style: context.textStyles.titleSmall),
                    const SizedBox(height: 2),
                    Text(tip.body,
                        style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
