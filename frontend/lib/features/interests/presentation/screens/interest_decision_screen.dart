import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../controllers/interests_controller.dart';

/// Full-screen accept/decline for one pending received interest —
/// screen 37. Reached by tapping a pending row on the Interests tab.
class InterestDecisionScreen extends ConsumerWidget {
  final String interestId;
  const InterestDecisionScreen({super.key, required this.interestId});

  Future<void> _respond(BuildContext context, WidgetRef ref, bool accept, String profileId) async {
    await ref.read(interestsActionsProvider).respond(interestId, accept);
    if (!context.mounted) return;

    if (!accept) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Interest declined.')),
      );
      context.pop();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Interest accepted — you can now chat.')),
    );

    // Accepting creates a conversation server-side — refetch (rather than
    // trust a possibly-stale cached list) so we can find the partner's
    // conversation ID (the chat window is keyed by *user* ID, whereas the
    // interest record only carries their *profile* ID) and open it
    // directly instead of just popping back to the interests list.
    ref.invalidate(conversationsProvider);
    try {
      final conversations = await ref.read(conversationsProvider.future);
      if (!context.mounted) return;
      final conversation =
          conversations.where((c) => c.withProfile.id == profileId).firstOrNull;
      if (conversation != null) {
        context.pushReplacement(AppRoutes.chatWindowPath(conversation.id));
        return;
      }
    } catch (_) {
      // Fall through to the plain pop below — the accept itself already
      // succeeded, only the follow-up navigation convenience failed.
    }
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(receivedInterestsProvider).valueOrNull ?? const [];
    final record = records.where((r) => r.id == interestId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Interest received')),
      body: record == null
          ? Center(
              child: Text('This interest is no longer available.',
                  style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
            )
          : SafeArea(
              child: SingleChildScrollView(
                // A Column relying on Spacer() for vertical centering only
                // stays safe from overflow when its *fixed* content (avatar
                // + name + buttons) fits the screen — a long name wrapping
                // to two lines, or larger system font scaling, could still
                // push total height past the screen with no scroll
                // fallback. Wrapping in a scroll view (with fixed gaps
                // instead of flexible Spacers, which can't live inside an
                // unbounded-height scroll view) removes that risk entirely.
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.xl),
                    ProfileAvatar(name: record.profile.name, size: 120),
                    const SizedBox(height: AppSpacing.lg),
                    Text('${record.profile.name}, ${record.profile.age}',
                        textAlign: TextAlign.center, style: context.textStyles.headlineMedium),
                    const SizedBox(height: 4),
                    Text('${record.profile.profession} · ${record.profile.city}',
                        textAlign: TextAlign.center,
                        style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
                    const SizedBox(height: AppSpacing.md),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.profileDetailPath(record.profile.id)),
                      child: const Text('View full profile'),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      '${record.profile.name.split(' ').first} has expressed interest in your profile.',
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _respond(context, ref, false, record.profile.id),
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _respond(context, ref, true, record.profile.id),
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
