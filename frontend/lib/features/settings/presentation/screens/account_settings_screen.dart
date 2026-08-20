import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';

/// "Account Settings" / "Contact Filters" from the menu, folded into one
/// screen: the one real backend-backed setting here is profile
/// visibility (public/private) — there's no separate "contact filters"
/// concept on the backend beyond that.
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  bool _saving = false;

  Future<void> _setVisibility(bool public) async {
    setState(() => _saving = true);
    final controller = ref.read(profileCreationControllerProvider.notifier);
    controller.update((p) => p.copyWith(visibility: public ? 'public' : 'private'));
    final ok = await controller.submit();
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final isPublic = draft.visibility != 'private';

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Profile visibility', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Public profiles show up in search and match results. '
            'Private profiles are only visible to people you\'ve already connected with.',
            style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: context.colors.line),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Public profile'),
              value: isPublic,
              onChanged: _saving ? null : _setVisibility,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block_rounded),
            title: const Text('Blocked members'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(AppRoutes.blockedUsers),
          ),
        ],
      ),
    );
  }
}
