import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/misc/app_file_image.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';

/// "Account on hold" — gate before the rest of the app: a selfie check
/// against the profile photo. If there's no profile photo yet, prompts
/// for one first.
class VerificationPromptScreen extends ConsumerWidget {
  const VerificationPromptScreen({super.key});

  Future<void> _startVerification(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(profileCreationControllerProvider).draft;
    if (draft.profilePhotoUrl == null) {
      await _requirePhotoSheet(context, ref);
      return;
    }
    if (context.mounted) context.push(AppRoutes.takeSelfie);
  }

  Future<void> _requirePhotoSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PhotoRequiredSheet(
        onPhotoAdded: () {
          Navigator.of(sheetContext).pop();
          _showAddedThenContinue(context);
        },
      ),
    );
  }

  Future<void> _showAddedThenContinue(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PhotoAddedDialog(),
    );
    if (context.mounted) context.push(AppRoutes.takeSelfie);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(profileCreationControllerProvider).draft;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              Text('Account on hold',
                  style: context.textStyles.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'As part of our routine safety checks, please complete a quick selfie verification to continue using your account',
                textAlign: TextAlign.center,
                style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Stack(
                children: [
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: context.colors.accentSoft,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: draft.profilePhotoUrl != null
                        ? AppFileImage(path: draft.profilePhotoUrl!, fit: BoxFit.cover)
                        : Icon(Icons.person_rounded, size: 72, color: context.colors.accent),
                  ),
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.colors.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.colors.bg, width: 3),
                      ),
                      child: const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              PrimaryButton(
                label: 'Verify with Selfie',
                onPressed: () => _startVerification(context, ref),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_outlined, size: 16, color: context.colors.muted),
                  const SizedBox(width: 6),
                  Text('Verification Selfies are NOT shown to others.',
                      style: context.textStyles.bodySmall),
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

class _PhotoRequiredSheet extends ConsumerWidget {
  final VoidCallback onPhotoAdded;
  const _PhotoRequiredSheet({required this.onPhotoAdded});

  Future<void> _addPhoto(WidgetRef ref) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      ref.read(profileCreationControllerProvider.notifier).update((p) => p.copyWith(
            photoUrls: [...p.photoUrls, picked.path],
            profilePhotoUrl: picked.path,
          ));
      onPhotoAdded();
    } catch (_) {
      // Picker unavailable on this platform/simulator — non-fatal for the demo.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: context.colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Photo Required to Verify', style: context.textStyles.headlineSmall),
            const SizedBox(height: 6),
            Text('Add photo to start verification',
                style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Add Profile Photo', onPressed: () => _addPhoto(ref)),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _PhotoAddedDialog extends StatefulWidget {
  const _PhotoAddedDialog();

  @override
  State<_PhotoAddedDialog> createState() => _PhotoAddedDialogState();
}

class _PhotoAddedDialogState extends State<_PhotoAddedDialog> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.bg,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: context.colors.success, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text('Photo added successfully', style: context.textStyles.titleMedium),
            const SizedBox(height: 6),
            Text("We'll now match your selfie with this Photo",
                textAlign: TextAlign.center,
                style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
          ],
        ),
      ),
    );
  }
}
