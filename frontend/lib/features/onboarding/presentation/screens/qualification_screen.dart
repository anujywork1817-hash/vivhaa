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
  'M.A', 'MSW', 'B.Sc', 'M.Sc', 'MBA', 'MBBS', 'MD', 'CA', 'CS', 'LLB', 'LLM', 'PhD',
];

class QualificationScreen extends ConsumerStatefulWidget {
  const QualificationScreen({super.key});

  @override
  ConsumerState<QualificationScreen> createState() => _QualificationScreenState();
}

class _QualificationScreenState extends ConsumerState<QualificationScreen> {
  late final _collegeController =
      TextEditingController(text: ref.read(profileCreationControllerProvider).draft.college);

  @override
  void dispose() {
    _collegeController.dispose();
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
            value: draft.highestEducation,
            options: _qualifications,
            onSelected: (v) => controller.update((p) => p.copyWith(highestEducation: v)),
          ),
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
