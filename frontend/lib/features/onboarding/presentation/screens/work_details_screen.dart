import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/income_brackets.dart';
import '../../../../shared/widgets/inputs/app_select_field.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../controllers/profile_creation_controller.dart';

// Sourced from the shared table so these labels stay in lockstep with the
// rupee figures the repository maps them to and back.
final _incomeOptions = incomeBracketLabels;
const _workWithOptions = [
  'Private Company', 'Government / Public Sector', 'Defense / Civil Services',
  'Business / Self Employed', 'Not Working',
];
const _professions = [
  'Software Engineer', 'Doctor', 'Chartered Accountant', 'Architect', 'Teacher',
  'Marketing Manager', 'Civil Servant', 'Lawyer', 'Entrepreneur', 'Banker',
  'Admin Professional', 'Human Resources Professional', 'Actor', 'Advertising Professional',
  'Entertainment Professional', 'Event Manager', 'Journalist',
];

class WorkDetailsScreen extends ConsumerStatefulWidget {
  const WorkDetailsScreen({super.key});

  @override
  ConsumerState<WorkDetailsScreen> createState() => _WorkDetailsScreenState();
}

class _WorkDetailsScreenState extends ConsumerState<WorkDetailsScreen> {
  late final _companyController =
      TextEditingController(text: ref.read(profileCreationControllerProvider).draft.companyName);

  @override
  void dispose() {
    _companyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    final canContinue = draft.annualIncome != null && draft.workWith != null;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 6,
      stepCount: onboardingStepCount,
      title: 'Almost done with ${profileFor.possessive} profile!',
      headerIcon: Icons.work_rounded,
      onContinue: canContinue ? () => context.push(AppRoutes.photoUpload) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Annual income', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: '${profileFor.possessiveTitle} annual income *',
            value: draft.annualIncome,
            options: _incomeOptions,
            onSelected: (v) => controller.update((p) => p.copyWith(annualIncome: v)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Why is income required?', style: context.textStyles.bodySmall),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Why we ask for income'),
                    content: Text(
                        "It helps other members find a match compatible with their expectations — ${profileFor.subject} can always leave it out of ${profileFor.possessive} public profile later in Privacy settings."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
                child: Icon(Icons.help_outline_rounded, size: 16, color: context.colors.muted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Work details', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppSelectField(
            label: '${profileFor.possessiveTitle} employer type',
            value: draft.workWith,
            options: _workWithOptions,
            onSelected: (v) => controller.update((p) => p.copyWith(workWith: v)),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSelectField(
            label: '${profileFor.possessiveTitle} profession',
            value: draft.profession,
            options: _professions,
            onSelected: (v) => controller.update((p) => p.copyWith(profession: v)),
          ),
          if (draft.workWith != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: '${profileFor.possessiveTitle} current company name',
              hint: 'Specify current organization',
              controller: _companyController,
              onChanged: (v) => controller.update((p) => p.copyWith(companyName: v)),
            ),
          ],
        ],
      ),
    );
  }
}
