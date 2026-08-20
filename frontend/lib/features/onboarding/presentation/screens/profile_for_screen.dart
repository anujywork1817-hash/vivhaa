import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../controllers/profile_creation_controller.dart';

/// Some "profile is for" choices imply a gender (a son is male, a
/// daughter is female, ...) — mirrors how production matrimonial apps
/// skip asking a question whose answer is already known. Returns null for
/// roles where gender genuinely isn't determined by the choice (myself,
/// friend, relative), in which case the picker below still applies.
Gender? _impliedGender(ProfileFor? profileFor) {
  switch (profileFor) {
    case ProfileFor.son:
    case ProfileFor.brother:
      return Gender.male;
    case ProfileFor.daughter:
    case ProfileFor.sister:
      return Gender.female;
    default:
      return null;
  }
}

/// Combines "who is this profile for" with gender in one screen — gender
/// only reveals once a profile-for choice is made, so the screen reads as
/// a short progressive form rather than two separate steps.
class ProfileForScreen extends ConsumerWidget {
  const ProfileForScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final canContinue = draft.profileFor != null && draft.gender != null;
    final showGenderPicker =
        draft.profileFor != null && _impliedGender(draft.profileFor) == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Create a profile')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This Profile is for', style: context.textStyles.headlineMedium),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: ProfileFor.values.map((option) {
                        return _PillChoice(
                          label: option.label,
                          selected: draft.profileFor == option,
                          onTap: () {
                            final implied = _impliedGender(option);
                            controller.update((p) => p.copyWith(
                                  profileFor: option,
                                  gender: implied,
                                ));
                          },
                        );
                      }).toList(),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: !showGenderPicker
                          ? const SizedBox.shrink()
                          : Padding(
                              key: const ValueKey('gender'),
                              padding: const EdgeInsets.only(top: AppSpacing.xxl),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${draft.profileFor!.possessiveTitle} Gender',
                                      style: context.textStyles.headlineSmall),
                                  const SizedBox(height: AppSpacing.md),
                                  Wrap(
                                    spacing: AppSpacing.md,
                                    runSpacing: AppSpacing.md,
                                    children: Gender.values.map((gender) {
                                      return _PillChoice(
                                        label: gender.label,
                                        selected: draft.gender == gender,
                                        onTap: () =>
                                            controller.update((p) => p.copyWith(gender: gender)),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: context.colors.line),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: context.colors.gold,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.priority_high_rounded,
                                size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Vivaha is built for genuine match-seekers. Any falsification, '
                              'commercial use or profiles by marriage bureaus are strictly '
                              'prohibited and may be reported to law enforcement.',
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: context.colors.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: PrimaryButton(
                label: 'Continue',
                onPressed: canContinue ? () => context.push(AppRoutes.nameDob) : null,
                trailingIcon: Icons.arrow_forward_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PillChoice({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? context.colors.accentSoft : context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: selected ? context.colors.accent : context.colors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: selected
                  ? Icon(Icons.check_circle_rounded,
                      key: const ValueKey('checked'), size: 18, color: context.colors.accent)
                  : Icon(Icons.circle_outlined,
                      key: const ValueKey('unchecked'), size: 18, color: context.colors.line),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? context.colors.accent : context.colors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
