import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/rating/app_rating_controller.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../../../premium/presentation/controllers/premium_controller.dart';

/// Full account/settings hub, reached via the hamburger icon on Home —
/// not a bottom-nav tab. Matches the reference's "My Shaadi" menu.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  Future<void> _shareProfile(WidgetRef ref) async {
    final draft = ref.read(profileCreationControllerProvider).draft;
    final name = draft.fullName ?? 'My';
    // The shareable short code, not the internal UUID — this is what a
    // recipient can actually search for via "Search by Profile ID".
    final code = draft.profileCode;
    final lines = [
      "$name's profile on Vivah",
      if (draft.age != null) 'Age: ${draft.age}',
      if (draft.city != null) 'City: ${draft.city}',
      if (draft.profession != null) 'Profession: ${draft.profession}',
      if (code.isNotEmpty) 'Profile ID: $code',
    ];
    await Share.share(lines.join('\n'));
  }

  Future<void> _rateApp(BuildContext context, WidgetRef ref) async {
    final submitted = await showDialog<int>(
      context: context,
      builder: (_) => const _RatingDialog(),
    );
    if (submitted == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Thanks for your feedback!')),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime with the same account.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    ref.read(profileCreationControllerProvider.notifier).reset();
    if (context.mounted) context.go(AppRoutes.splash);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final user = ref.watch(authControllerProvider).user;
    final name = draft.fullName ?? user?.phoneOrEmail ?? 'Your profile';
    // The short backend-generated code (e.g. "VV100016"), never the raw
    // UUID — that's an internal database key, not something to show or
    // ask a member to read out.
    final profileId = draft.profileCode.isNotEmpty ? draft.profileCode : '—';
    final isPremium = ref.watch(mySubscriptionProvider).valueOrNull?.isPremium ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            // Extra bottom room only when the pinned Upgrade bar is there
            // to be scrolled clear of.
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, isPremium ? AppSpacing.lg : 104),
            children: [
              Row(
                children: [
                  ProfileAvatar(name: name, size: 56, photoUrl: draft.profilePhotoUrl),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(name, style: context.textStyles.titleMedium, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 4),
                            Icon(Icons.verified_rounded, size: 16, color: context.colors.accent),
                          ],
                        ),
                        if (isPremium) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: AppColors.premiumGradient,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.workspace_premium_rounded, size: 12, color: Colors.white),
                                SizedBox(width: 4),
                                Text('PREMIUM MEMBER',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        InkWell(
                          onTap: profileId == '—'
                              ? null
                              : () async {
                                  await Clipboard.setData(ClipboardData(text: profileId));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Profile ID $profileId copied.')),
                                    );
                                  }
                                },
                          child: Row(
                            children: [
                              Flexible(
                                child: Text('Profile ID: $profileId',
                                    style: context.textStyles.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.copy_rounded, size: 14, color: context.colors.muted),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _MenuGroup(
                rows: [
                  _Row(
                    icon: Icons.edit_rounded,
                    label: 'View and Edit your Profile',
                    onTap: () => context.push(AppRoutes.editProfile),
                  ),
                  _Row(
                    icon: Icons.file_download_outlined,
                    label: 'Share Profile',
                    onTap: () => _shareProfile(ref),
                  ),
                ],
              ),
              // Upsell strip — pointless for someone who already pays.
              if (!isPremium)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.colors.ink,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('VIP', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: Text('VIP Vivah', style: context.textStyles.titleSmall)),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)),
                        // No invite/VIP tier exists on the backend — only
                        // the free and premium subscription plans do. Say
                        // that instead of leaving a no-op button.
                        onPressed: () => showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('VIP Vivah'),
                            content: const Text(
                                'Our invite-only VIP tier isn\'t open yet. Premium membership is '
                                'available today and unlocks chat, unlimited interests and contact details.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                child: const Text('Got it'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('GET INVITED'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text('Discover Your Matches', style: context.textStyles.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _MenuGroup(
                rows: [
                  _Row(
                    icon: Icons.star_border_rounded,
                    label: 'Favourites',
                    onTap: () => context.push(AppRoutes.favourites),
                  ),
                  _Row(
                    icon: Icons.visibility_outlined,
                    label: 'Profile Visitors',
                    onTap: () => context.push(AppRoutes.visitors),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Options & Settings', style: context.textStyles.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _MenuGroup(
                rows: [
                  _Row(
                    icon: Icons.badge_outlined,
                    label: 'Partner Preferences',
                    onTap: () => context.push(AppRoutes.partnerPreferences, extra: true),
                  ),
                  _Row(
                    icon: Icons.settings_outlined,
                    label: 'Account Settings',
                    onTap: () => context.push(AppRoutes.accountSettings),
                  ),
                  _Row(
                    icon: Icons.tune_rounded,
                    label: 'Preferences',
                    onTap: () => context.push(AppRoutes.preferences),
                  ),
                  _Row(
                    icon: Icons.help_outline_rounded,
                    label: 'Help & Support',
                    onTap: () => context.push(AppRoutes.aiAssistant),
                  ),
                  _Row(
                    icon: Icons.shield_outlined,
                    label: 'Be Safe Online',
                    onTap: () => context.push(AppRoutes.safetyTips),
                  ),
                  _Row(
                    icon: Icons.block_outlined,
                    label: 'Blocked Users',
                    onTap: () => context.push(AppRoutes.blockedUsers),
                  ),
                  _Row(
                    icon: Icons.star_outline_rounded,
                    label: 'Rate the App',
                    onTap: () => _rateApp(context, ref),
                  ),
                ],
              ),
              if (user?.isAdmin == true) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Admin', style: context.textStyles.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                _MenuGroup(
                  rows: [
                    _Row(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Admin Dashboard',
                      onTap: () => context.push(AppRoutes.adminDashboard),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              TextButton(onPressed: () => _signOut(context, ref), child: const Text('Sign out')),
              const SizedBox(height: AppSpacing.lg),
              InkWell(
                onTap: () => context.push(AppRoutes.termsConditions),
                child: Text('Terms & Conditions',
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.colors.accent, decoration: TextDecoration.underline)),
              ),
              const SizedBox(height: 4),
              Text('Copyright © 1996-2026 Vivah.com',
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
              Text('Version 1.0.0',
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
            ],
          ),
          // Nothing left to upgrade to once you're premium — the pinned
          // bar (and its discount badge) only make sense for free members.
          if (!isPremium)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      border: Border(top: BorderSide(color: context.colors.line)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push(AppRoutes.premiumPaywall),
                        icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                        label: const Text('Upgrade Now'),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.colors.success,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                        border: Border.all(color: context.colors.bg, width: 2),
                      ),
                      child: const Text('% UPTO 55% OFF',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Groups a set of [_Row] menu items into one white, bordered, rounded
/// card with thin dividers between rows — the same card language used
/// for every other list surface in the app.
class _MenuGroup extends StatelessWidget {
  final List<_Row> rows;
  const _MenuGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.colors.line),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Row({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      minVerticalPadding: AppSpacing.sm,
      leading: Icon(icon, color: context.colors.muted),
      title: Text(label, style: context.textStyles.bodyLarge),
      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: context.colors.muted),
      onTap: onTap,
    );
  }
}

/// 5-star picker. Opens pre-filled with whatever the user picked last
/// time ([appRatingProvider], persisted via SharedPreferences) instead of
/// always starting blank, and pops with the submitted star count (or null
/// if dismissed without submitting).
class _RatingDialog extends ConsumerStatefulWidget {
  const _RatingDialog();

  @override
  ConsumerState<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends ConsumerState<_RatingDialog> {
  late int _selected = ref.read(appRatingProvider) ?? 0;
  late final _feedbackController =
      TextEditingController(text: ref.read(appRatingFeedbackProvider) ?? '');

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previouslyRated = ref.watch(appRatingProvider) != null;

    return AlertDialog(
      title: const Text('Enjoying Vivah?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              previouslyRated
                  ? 'You can update your rating any time.'
                  : 'Tap a star to rate your experience.',
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            // Each star sized to share the row equally rather than at its
            // IconButton's default (48dp) touch-target width, which on a
            // narrow dialog pushed the fifth star a few pixels past the
            // edge — a layout overflow, not a rendering bug.
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Expanded(
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _selected = i),
                      icon: Icon(
                        i <= _selected ? Icons.star_rounded : Icons.star_border_rounded,
                        color: context.colors.gold,
                        size: 32,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _feedbackController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Tell us what\'s working or what could be better (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selected == 0
              ? null
              : () {
                  ref.read(appRatingProvider.notifier).setRating(_selected);
                  final feedback = _feedbackController.text.trim();
                  if (feedback.isNotEmpty) {
                    ref.read(appRatingFeedbackProvider.notifier).setFeedback(feedback);
                  }
                  Navigator.of(context).pop(_selected);
                },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
