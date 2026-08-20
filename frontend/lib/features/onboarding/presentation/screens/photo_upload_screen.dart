import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/misc/app_file_image.dart';
import '../controllers/profile_creation_controller.dart';

/// "Add Photos to complete your Profile" — a single centered avatar
/// picker rather than the multi-photo grid used elsewhere, matching the
/// reference's focused first-photo step.
class PhotoUploadScreen extends ConsumerWidget {
  const PhotoUploadScreen({super.key});

  Future<void> _pick(WidgetRef ref, ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      ref.read(profileCreationControllerProvider.notifier).update((p) => p.copyWith(
            photoUrls: [...p.photoUrls, picked.path],
            profilePhotoUrl: picked.path,
          ));
    } catch (_) {
      // Picker unavailable on this platform/simulator — non-fatal for the demo.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final hasPhoto = draft.profilePhotoUrl != null;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              Stack(
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: context.colors.line, width: 1.4),
                      color: context.colors.surface,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasPhoto
                        ? AppFileImage(path: draft.profilePhotoUrl!, fit: BoxFit.cover)
                        : Icon(Icons.person_outline_rounded, size: 72, color: context.colors.muted),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _pick(ref, ImageSource.gallery),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: context.colors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.colors.bg, width: 2),
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Add Photos\nto complete ${profileFor.possessive} Profile',
                  textAlign: TextAlign.center, style: context.textStyles.headlineMedium),
              const SizedBox(height: 6),
              Text('Photo Privacy controls available in Settings',
                  textAlign: TextAlign.center,
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ref, ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Add from Gallery'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: Colors.white,
                    side: BorderSide(color: context.colors.accent),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: () => _pick(ref, ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Use Camera'),
              ),
              const Spacer(flex: 2),
              if (hasPhoto)
                PrimaryButton(
                  label: 'Continue',
                  onPressed: () => context.push(AppRoutes.aboutMe),
                )
              else
                TextButton(
                  onPressed: () => context.push(AppRoutes.aboutMe),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('Add Photos Later'),
                      Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
