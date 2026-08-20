import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/inputs/app_date_picker_field.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../controllers/profile_creation_controller.dart';

/// Matrimony sign-ups are adults only, and the partner-preference sliders
/// elsewhere already clamp to 18–65 — so 18 is the floor here too. The upper
/// bound just keeps the year grid to a sane length.
const minSignupAge = 18;
const maxSignupAge = 100;

/// First form step right after "This Profile is for" — just name and date
/// of birth, kept on their own screen rather than folded into the longer
/// basic-details step.
class NameDobScreen extends ConsumerStatefulWidget {
  const NameDobScreen({super.key});

  @override
  ConsumerState<NameDobScreen> createState() => _NameDobScreenState();
}

class _NameDobScreenState extends ConsumerState<NameDobScreen> {
  late final _firstNameController = TextEditingController(
      text: ref.read(profileCreationControllerProvider).draft.firstName);
  late final _lastNameController = TextEditingController(
      text: ref.read(profileCreationControllerProvider).draft.lastName);

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    final canContinue = (draft.firstName ?? '').trim().isNotEmpty &&
        (draft.lastName ?? '').trim().isNotEmpty &&
        draft.dateOfBirth != null;

    final profileFor = draft.profileFor ?? ProfileFor.myself;

    // Computed per build rather than cached in state so a session left open
    // across midnight can't offer a date that has since gone out of range.
    final today = DateTime.now();
    final oldestAllowed = DateTime(today.year - maxSignupAge, today.month, today.day);
    final youngestAllowed = DateTime(today.year - minSignupAge, today.month, today.day);

    return OnboardingStepScaffold(
      stepIndex: 1,
      stepCount: onboardingStepCount,
      title: '${profileFor.possessiveTitle} name',
      headerIcon: Icons.badge_rounded,
      onContinue: canContinue ? () => context.push(AppRoutes.religionCommunity) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'First name',
            controller: _firstNameController,
            onChanged: (v) => controller.update((p) => p.copyWith(firstName: v)),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Last name',
            controller: _lastNameController,
            onChanged: (v) => controller.update((p) => p.copyWith(lastName: v)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Date of birth', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppDatePickerField(
            label: 'Date of birth',
            hint: 'Tap to pick a date',
            value: draft.dateOfBirth,
            firstDate: oldestAllowed,
            lastDate: youngestAllowed,
            onSelected: (date) => controller.update((p) => p.copyWith(dateOfBirth: date)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You must be at least $minSignupAge to create a profile.',
            style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
          ),
        ],
      ),
    );
  }
}
