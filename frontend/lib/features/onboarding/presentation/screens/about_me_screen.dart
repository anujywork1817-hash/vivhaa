import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../controllers/profile_creation_controller.dart';

String _generateBio({String? education, String? profession}) {
  final educationPart = education != null
      ? 'In terms of education, I have completed my $education from a renowned institution. '
      : '';
  final professionPart =
      profession != null ? 'Currently, I am working as a $profession. ' : '';
  return 'Thank you for showing interest in my profile. Here are a few things about me. '
      '$educationPart$professionPart'
      'My sense of priorities is well balanced. I treat life as a journey rather than a race. '
      "Someone who values honesty and a good sense of humor would make a great match.";
}

class AboutMeScreen extends ConsumerStatefulWidget {
  const AboutMeScreen({super.key});

  @override
  ConsumerState<AboutMeScreen> createState() => _AboutMeScreenState();
}

class _AboutMeScreenState extends ConsumerState<AboutMeScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(profileCreationControllerProvider).draft;
    final initialText = draft.aboutMe ??
        _generateBio(education: draft.highestEducation, profession: draft.profession);
    _controller = TextEditingController(text: initialText);
    // Persist the auto-generated draft immediately so "Continue" reflects
    // what's actually shown, even if the user never edits it.
    if (draft.aboutMe == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(profileCreationControllerProvider.notifier)
            .update((p) => p.copyWith(aboutMe: initialText));
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creationController = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 7,
      stepCount: onboardingStepCount,
      title: 'We have added a short description about ${profileFor.subject}',
      headerIcon: Icons.edit_document,
      onContinue: (draft.aboutMe != null && draft.aboutMe!.trim().length >= 20)
          ? () => context.push(AppRoutes.verificationPrompt)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About ${profileFor.subjectTitle}', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            maxLines: 8,
            maxLength: 4000,
            onChanged: (v) => creationController.update((p) => p.copyWith(aboutMe: v)),
          ),
          Text('Edit the text above to make it more personal.',
              style: context.textStyles.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: () => creationController
                .update((p) => p.copyWith(matchmakingOptOut: !(p.matchmakingOptOut ?? false))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: draft.matchmakingOptOut ?? false,
                  onChanged: (v) =>
                      creationController.update((p) => p.copyWith(matchmakingOptOut: v ?? false)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            "Do not add ${profileFor.possessive} profile to Vivah's affiliated Matchmaking",
                            style: context.textStyles.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => showDialog(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Affiliated matchmaking'),
                              content: const Text(
                                  "By default, your profile may also be shown through Vivah's partner matchmaking services for extra visibility. Check this box to opt out."),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                  child: const Text('Got it'),
                                ),
                              ],
                            ),
                          ),
                          child: Icon(Icons.help_outline_rounded,
                              size: 16, color: context.colors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
