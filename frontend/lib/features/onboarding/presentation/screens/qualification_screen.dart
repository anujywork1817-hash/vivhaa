import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/inputs/app_select_field.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../controllers/profile_creation_controller.dart';

const _qualifications = [
  'B.E / B.Tech', 'M.E / M.Tech', 'M.S Engineering', 'B.Eng (Hons)', 'M.Eng (Hons)',
  'Engineering Diploma', 'B.A', 'B.Ed', 'BJMC', 'BFA', 'B.Arch', 'B.Des', 'BMM', 'MFA', 'M.Ed',
  'M.A', 'MSW', 'B.Sc', 'M.Sc', 'MBA', 'MBBS', 'MD', 'CA', 'CS', 'LLB', 'LLM', 'PhD', 'Other',
];

class QualificationScreen extends ConsumerStatefulWidget {
  const QualificationScreen({super.key});

  @override
  ConsumerState<QualificationScreen> createState() => _QualificationScreenState();
}

class _QualificationScreenState extends ConsumerState<QualificationScreen> {
  late final _collegeController =
      TextEditingController(text: ref.read(profileCreationControllerProvider).draft.college);

  // Prefilled with the existing value only if it's a custom entry (i.e.
  // "Other" was picked on an earlier visit) — otherwise this starts empty
  // and the field only appears once "Other" is actually selected below.
  // Mirrors WorkDetailsScreen's identical custom-profession pattern.
  late final _customQualificationController = TextEditingController(
    text: _isCustomQualification(ref.read(profileCreationControllerProvider).draft.highestEducation)
        ? ref.read(profileCreationControllerProvider).draft.highestEducation
        : null,
  );

  /// True once the member has a qualification that isn't one of the
  /// listed options — either "Other" was just picked (value is literally
  /// "Other", box not filled in yet) or they typed something last time
  /// and came back to this step.
  static bool _isCustomQualification(String? qualification) =>
      qualification != null && qualification != 'Other' && !_qualifications.contains(qualification);

  @override
  void dispose() {
    _collegeController.dispose();
    _customQualificationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 5,
      stepCount: onboardingStepCount,
      title: 'Great! Few more details',
      headerIcon: Icons.school_rounded,
      onContinue:
          draft.highestEducation != null ? () => context.push(AppRoutes.workDetails) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Highest qualification', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: '${profileFor.possessiveTitle} highest qualification *',
            // Showing "Other" once a custom value is in place (rather
            // than the raw typed text) keeps the picker's own list of
            // options meaningful — the actual text lives in the field
            // below, which is the thing that's actually saved.
            value: _isCustomQualification(draft.highestEducation) ? 'Other' : draft.highestEducation,
            options: _qualifications,
            onSelected: (v) {
              if (v == 'Other') {
                // Reopening "Other" after already having typed something
                // shouldn't blank it out — re-save whatever's still in
                // the box, or leave highestEducation as the "Other"
                // sentinel until they type, same as a first-time pick.
                controller.update((p) => p.copyWith(
                      highestEducation: _customQualificationController.text.trim().isEmpty
                          ? v
                          : _customQualificationController.text,
                    ));
                return;
              }
              _customQualificationController.clear();
              controller.update((p) => p.copyWith(highestEducation: v));
            },
          ),
          if (draft.highestEducation == 'Other' || _isCustomQualification(draft.highestEducation)) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: '${profileFor.possessiveTitle} highest qualification',
              hint: 'Tell us what ${profileFor.subject} studied',
              controller: _customQualificationController,
              onChanged: (v) => controller.update((p) => p.copyWith(highestEducation: v)),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          Text('College', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: '${profileFor.possessiveTitle} college',
            controller: _collegeController,
            onChanged: (v) => controller.update((p) => p.copyWith(college: v)),
          ),
        ],
      ),
    );
  }
}
