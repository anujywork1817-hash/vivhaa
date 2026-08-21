import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../dashboard/presentation/controllers/dashboard_controller.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../controllers/profile_creation_controller.dart';

/// "Let's get started by Connecting with few of your Matches" — a batch
/// of real recommended matches (same source as the dashboard's
/// "Recommended for you"), all checked by default; unchecking is
/// allowed, connecting sends a real interest to each one selected.
class ConnectMatchesScreen extends ConsumerStatefulWidget {
  const ConnectMatchesScreen({super.key});

  @override
  ConsumerState<ConnectMatchesScreen> createState() => _ConnectMatchesScreenState();
}

class _ConnectMatchesScreenState extends ConsumerState<ConnectMatchesScreen> {
  Set<String>? _selected;
  bool _connecting = false;

  Future<void> _connect(List<MatchProfile> suggested) async {
    setState(() => _connecting = true);
    final actions = ref.read(interestsActionsProvider);
    for (final profile in suggested.where((p) => _selected!.contains(p.id))) {
      await actions.send(profile);
    }
    if (mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final profileFor =
        ref.watch(profileCreationControllerProvider).draft.profileFor ?? ProfileFor.myself;
    final matchesAsync = ref.watch(recommendedMatchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded, size: 16, color: context.colors.accent),
            const SizedBox(width: 4),
            Text('Vivaha', style: TextStyle(fontFamily: 'Georgia', color: context.colors.accent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load suggested matches',
          message: 'You can still continue — matches will show up on your dashboard.',
          actionLabel: 'Continue',
          onAction: () => context.go(AppRoutes.home),
        ),
        data: (suggested) {
          if (suggested.isEmpty) {
            return EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No suggestions yet',
              message: "We'll have matches ready once ${profileFor.possessive} profile is live.",
              actionLabel: 'Continue',
              onAction: () => context.go(AppRoutes.home),
            );
          }

          _selected ??= suggested.map((p) => p.id).toSet();
          final allSelected = _selected!.length == suggested.length;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          "Let's get started by Connecting\nwith few of ${profileFor.possessive} Matches",
                          style: context.textStyles.headlineMedium),
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () => setState(() {
                            _selected =
                                allSelected ? {} : suggested.map((p) => p.id).toSet();
                          }),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Select All', style: context.textStyles.bodyMedium),
                              const SizedBox(width: 6),
                              Icon(
                                allSelected
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: context.colors.accent,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (final profile in suggested)
                        _MatchTile(
                          profile: profile,
                          selected: _selected!.contains(profile.id),
                          onToggle: () => setState(() {
                            _selected!.contains(profile.id)
                                ? _selected!.remove(profile.id)
                                : _selected!.add(profile.id);
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                child: PrimaryButton(
                  label: 'Connect with selected',
                  loading: _connecting,
                  onPressed: _selected!.isEmpty ? null : () => _connect(suggested),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  final MatchProfile profile;
  final bool selected;
  final VoidCallback onToggle;
  const _MatchTile({required this.profile, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: context.colors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(name: profile.name, size: 64, borderRadius: BorderRadius.circular(10)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name,
                      style: context.textStyles.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${profile.age} yrs, ${profile.heightLabel}',
                      style: context.textStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('${profile.religion}, ${profile.community ?? ''}',
                      style: context.textStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(profile.profession,
                      style: context.textStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(profile.city,
                      style: context.textStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? context.colors.ink : context.colors.surface,
                border: Border.all(color: context.colors.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
