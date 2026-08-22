import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../authentication/data/api_auth_repository.dart';
import '../../../authentication/domain/auth_repository.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';

final _accountInfoProvider =
    FutureProvider.autoDispose<AccountInfo>((ref) async {
  final result = await ref.watch(authRepositoryProvider).getAccount();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

/// "Account Settings" / "Contact Filters" from the menu, folded into one
/// screen: the one real backend-backed setting here is profile
/// visibility (public/private) — there's no separate "contact filters"
/// concept on the backend beyond that.
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  bool _saving = false;
  bool _deleting = false;

  /// Two-step dialog flow: enter a phone number, send an OTP to it, then
  /// enter the code to attach it to this account. Only offered when the
  /// account has none (Google/email signups start with none) — this is
  /// what lets the chat contact-share feature hand out a real mobile
  /// number for those accounts instead of always falling back to email.
  Future<void> _addPhoneNumber() async {
    final phoneController = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add phone number'),
        content: TextField(
          controller: phoneController,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '+919876543210'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(phoneController.text.trim()),
            child: const Text('Send code'),
          ),
        ],
      ),
    );
    phoneController.dispose();
    if (phone == null || phone.isEmpty || !mounted) return;

    final requestResult =
        await ref.read(authRepositoryProvider).requestLinkPhoneOtp(phone);
    if (!mounted) return;
    final requestFailure =
        requestResult.when(success: (_) => null, failure: (f) => f);
    if (requestFailure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(requestFailure.message)));
      return;
    }

    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter verification code'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(hintText: '6-digit code sent to $phone'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(codeController.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    codeController.dispose();
    if (code == null || code.isEmpty || !mounted) return;

    final confirmResult =
        await ref.read(authRepositoryProvider).confirmLinkPhone(phone, code);
    if (!mounted) return;
    confirmResult.when(
      success: (_) {
        ref.invalidate(_accountInfoProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Phone number added.')));
      },
      failure: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3), content: Text(f.message))),
    );
  }

  Future<void> _setVisibility(bool public) async {
    setState(() => _saving = true);
    final controller = ref.read(profileCreationControllerProvider.notifier);
    controller
        .update((p) => p.copyWith(visibility: public ? 'public' : 'private'));
    final ok = await controller.submit();
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Could not save. Please try again.')));
    }
  }

  /// Two-step confirmation for an irreversible action: an explanatory
  /// dialog first, then a typed "DELETE" phrase — a plain Cancel/Confirm
  /// pair is too easy to tap through without reading, for something with
  /// no undo (see users.Handler.DeleteMe on the backend).
  Future<void> _deleteAccount() async {
    final understood = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deactivates your account. You will be signed out '
          'on all devices, your profile will no longer be visible to anyone, '
          'and this cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Continue',
                style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    if (understood != true || !mounted) return;

    final typedController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Type DELETE to confirm'),
        content: TextField(
          controller: typedController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'DELETE'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: typedController,
            builder: (_, value, __) {
              final canDelete = value.text.trim().toUpperCase() == 'DELETE';
              return TextButton(
                onPressed: canDelete
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text('Delete my account',
                    style: TextStyle(color: dialogContext.colors.danger)),
              );
            },
          ),
        ],
      ),
    );
    typedController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final failure =
        await ref.read(authControllerProvider.notifier).deleteAccount();
    if (!mounted) return;
    setState(() => _deleting = false);
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(failure.message)));
      return;
    }
    context.go(AppRoutes.splash);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final isPublic = draft.visibility != 'private';
    final accountInfo = ref.watch(_accountInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Phone number', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            'The number shared when someone you\'re chatting with requests your '
            'contact details.',
            style: context.textStyles.bodySmall
                ?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          accountInfo.when(
            data: (info) => info.phone != null
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(info.phone!),
                  )
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_ic_call_rounded),
                    title: const Text('Add phone number'),
                    subtitle: const Text(
                        'Not set — sharing contact will offer your email instead'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _addPhoneNumber,
                  ),
            loading: () => const SizedBox(
                height: 48,
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, __) => const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.error_outline_rounded),
              title: Text('Could not load phone number'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Profile visibility', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Public profiles show up in search and match results. '
            'Private profiles are only visible to people you\'ve already connected with.',
            style: context.textStyles.bodySmall
                ?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 4),
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
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_rounded,
                color: context.colors.danger),
            title: Text('Delete account',
                style: TextStyle(color: context.colors.danger)),
            subtitle: const Text('Permanently deactivate your account'),
            trailing: _deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _deleting ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }
}
