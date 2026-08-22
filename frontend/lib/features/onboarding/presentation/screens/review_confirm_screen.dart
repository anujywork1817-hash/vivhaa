import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/misc/app_file_image.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../controllers/profile_creation_controller.dart';

class ReviewConfirmScreen extends ConsumerWidget {
  const ReviewConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileCreationControllerProvider);
    final draft = state.draft;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 8,
      stepCount: onboardingStepCount,
      title: 'Review ${profileFor.possessive} profile',
      subtitle:
          'Here\'s what other members will see. You can edit any of this later.',
      continueLabel: 'Submit profile',
      loading: state.submitting,
      onContinue: () async {
        final notifier = ref.read(profileCreationControllerProvider.notifier);
        final ok = await notifier.submit();
        if (!context.mounted) return;
        final photoFailures =
            ref.read(profileCreationControllerProvider).photoUploadFailures;
        if (ok && photoFailures > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(photoFailures == 1
                ? "Your profile was saved, but the photo couldn't be uploaded. You can add it again from Edit Profile."
                : "Your profile was saved, but $photoFailures photos couldn't be uploaded. You can add them again from Edit Profile."),
          ));
        }
        if (ok) context.go(AppRoutes.welcomePending);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (draft.profilePhotoUrl != null)
            Center(
              child: ClipOval(
                child: AppFileImage(
                    path: draft.profilePhotoUrl!,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover),
              ),
            )
          else
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: context.colors.accentSoft,
                child: Icon(Icons.person_rounded,
                    size: 44, color: context.colors.accent),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          _ReviewSection(title: 'Basic details', rows: {
            'Name': draft.fullName ?? '—',
            'Age': draft.age?.toString() ?? '—',
            'Gender': draft.gender?.label ?? '—',
            'Marital status': draft.maritalStatus?.label ?? '—',
            'Height': draft.heightLabel,
            'City': draft.city ?? '—',
            'State': draft.state ?? '—',
            'Living in': draft.country ?? '—',
          }),
          _ReviewSection(title: 'Religion & community', rows: {
            'Religion': draft.religion ?? '—',
            'Community': draft.community ?? '—',
            'Sub-community': draft.subCommunity ?? '—',
          }),
          _ReviewSection(title: 'Education & career', rows: {
            'Qualification': draft.highestEducation ?? '—',
            'College': draft.college ?? '—',
            'Profession': draft.profession ?? '—',
            'Works with': draft.workWith ?? '—',
            'Company': draft.companyName ?? '—',
            'Annual income': draft.annualIncome ?? '—',
          }),
          _ReviewSection(title: 'Lifestyle', rows: {
            'Diet': draft.diet?.label ?? '—',
          }),
          if (draft.aboutMe != null && draft.aboutMe!.isNotEmpty) ...[
            Text('About', style: context.textStyles.titleSmall),
            const SizedBox(height: 6),
            Text(draft.aboutMe!, style: context.textStyles.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final Map<String, String> rows;
  const _ReviewSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: context.colors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: context.textStyles.titleSmall
                    ?.copyWith(color: context.colors.accent)),
            const SizedBox(height: 8),
            ...rows.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 140,
                          child:
                              Text(e.key, style: context.textStyles.bodySmall)),
                      Expanded(
                          child: Text(e.value,
                              style: context.textStyles.bodyMedium,
                              textAlign: TextAlign.right)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
