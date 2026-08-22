import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../blocked_users/presentation/controllers/blocked_users_controller.dart';
import '../../../favourites/presentation/controllers/favourites_controller.dart';
import '../../data/api_profile_detail_repository.dart';

const _reportReasons = [
  'Fake profile',
  'Inappropriate photos',
  'Asking for money',
  'Already married',
  'Other',
];

/// "More" menu on the profile-detail screen (and chat window's own "More"):
/// favourite toggle, report, block/unblock. Block is a semi-destructive
/// action (they immediately lose access to message you or view your
/// profile) so it goes behind a confirmation dialog rather than firing on
/// a single tap, and — since the profile/chat this sheet was opened from
/// becomes unreachable once blocked — [onBlocked] lets the caller navigate
/// somewhere sensible after a successful block instead of leaving a dead
/// screen behind. [isBlocked] switches the row to Unblock (no confirmation
/// needed — restoring access isn't destructive) when the caller already
/// knows this member is blocked, e.g. a chat that's currently locked.
class ProfileActionsSheet extends ConsumerWidget {
  final String profileId;
  final String name;
  final bool isBlocked;
  final VoidCallback? onBlocked;

  const ProfileActionsSheet({
    super.key,
    required this.profileId,
    required this.name,
    this.isBlocked = false,
    this.onBlocked,
  });

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Report this profile'),
        children: _reportReasons
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(r),
                  child: Text(r),
                ))
            .toList(),
      ),
    );
    if (reason == null || !context.mounted) return;
    Navigator.of(context).pop(); // close the actions sheet
    await ref
        .read(profileDetailRepositoryProvider)
        .reportProfile(profileId, reason);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Reported — thanks for letting us know.')),
      );
    }
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
            "They won't be able to message you or view your profile."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Block',
                style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(blockedUsersActionsProvider).block(profileId);
    if (!context.mounted) return;

    Navigator.of(context).pop(); // close the actions sheet
    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('$name has been blocked.')),
        );
        onBlocked?.call();
      },
      failure: (f) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3), content: Text(f.message)));
      },
    );
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final result =
        await ref.read(blockedUsersActionsProvider).unblock(profileId);
    if (!context.mounted) return;

    Navigator.of(context).pop(); // close the actions sheet
    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('$name has been unblocked.')));
      },
      failure: (f) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3), content: Text(f.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavourited = ref.watch(favouriteActionsProvider.select(
      (s) => s.favourited.contains(profileId),
    ));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(
                isFavourited ? Icons.star_rounded : Icons.star_border_rounded),
            title: Text(
                isFavourited ? 'Remove from favourites' : 'Add to favourites'),
            onTap: () {
              ref
                  .read(favouriteActionsProvider.notifier)
                  .toggleFavourite(profileId);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Report'),
            onTap: () => _report(context, ref),
          ),
          if (isBlocked)
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('Unblock'),
              onTap: () => _unblock(context, ref),
            )
          else
            ListTile(
              leading: Icon(Icons.block_rounded, color: context.colors.danger),
              title:
                  Text('Block', style: TextStyle(color: context.colors.danger)),
              onTap: () => _block(context, ref),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
