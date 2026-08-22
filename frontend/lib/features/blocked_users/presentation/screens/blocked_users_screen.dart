import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../controllers/blocked_users_controller.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  // Hides a row the instant Unblock is confirmed, before the network call
  // resolves — reverted (row reappears) if the call fails. The list itself
  // stays a plain FutureProvider (same pattern as Favourites/Shortlist);
  // this is purely a local, per-screen overlay on top of it.
  final Set<String> _optimisticallyRemoved = {};

  @override
  void initState() {
    super.initState();
    // Defensive: force a fresh fetch every time this screen opens rather
    // than trusting provider caching/invalidation from wherever the user
    // blocked/unblocked someone. Scheduled after the first frame so it
    // doesn't fire mid-build (invalidate() during build is unsafe) and
    // runs only once on mount, not on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(blockedUsersListProvider);
    });
  }

  Future<void> _unblock(String profileId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unblock $name?'),
        content: Text(
            '$name will be able to see your profile and contact you again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _optimisticallyRemoved.add(profileId));

    final result =
        await ref.read(blockedUsersActionsProvider).unblock(profileId);
    if (!mounted) return;

    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('$name has been unblocked.')));
        // The action already invalidated blockedUsersListProvider, so the
        // next successful fetch won't include this id anyway — clear our
        // own flag too rather than leave it lingering for a future id reuse.
        setState(() => _optimisticallyRemoved.remove(profileId));
      },
      failure: (f) {
        // Roll back: bring the row back and explain why.
        setState(() => _optimisticallyRemoved.remove(profileId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3), content: Text(f.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = ref.watch(blockedUsersListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Members')),
      body: _body(blocked),
    );
  }

  Widget _body(AsyncValue<List<MatchProfile>> blocked) {
    // Prefer showing the last-known list (filtered through the optimistic
    // overlay) over a full-screen spinner whenever one's available — the
    // unblock action's invalidate() triggers a background refetch, and
    // without this a successful optimistic removal would immediately be
    // clobbered by a loading spinner replacing the whole list.
    if (blocked.hasValue) {
      final profiles = blocked.value!
          .where((p) => !_optimisticallyRemoved.contains(p.id))
          .toList();
      if (profiles.isEmpty) {
        return const EmptyState(
          icon: Icons.block_rounded,
          title: 'No blocked members',
          message:
              'Members you block will show up here — you can unblock them anytime.',
        );
      }
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(blockedUsersListProvider),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: profiles.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final profile = profiles[index];
            return Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: context.colors.line),
              ),
              child: Row(
                children: [
                  ProfileAvatar(
                    name: profile.name,
                    photoUrl: profile.photoSeed,
                    size: 48,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name,
                            style: context.textStyles.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (profile.city.isNotEmpty)
                          Text(profile.city,
                              style: context.textStyles.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _unblock(profile.id, profile.name),
                    child: const Text('Unblock'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    if (blocked.hasError) {
      return const EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Something went wrong',
        message:
            'Could not load your blocked members. Pull to refresh to try again.',
      );
    }

    return const Center(child: CircularProgressIndicator());
  }
}
