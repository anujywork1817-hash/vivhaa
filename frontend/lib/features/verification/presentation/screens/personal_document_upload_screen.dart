import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../data/api_verification_repository.dart';
import '../controllers/personal_document_controller.dart';

/// Mandatory onboarding step, shown right after selfie verification:
/// the user must upload a supporting personal document (photo or PDF)
/// for admin review before continuing. There is no skip — if the user
/// has already submitted one (checked via [VerificationRepository.
/// listMine]), this screen fast-forwards past itself.
class PersonalDocumentUploadScreen extends ConsumerStatefulWidget {
  const PersonalDocumentUploadScreen({super.key});

  @override
  ConsumerState<PersonalDocumentUploadScreen> createState() =>
      _PersonalDocumentUploadScreenState();
}

class _PersonalDocumentUploadScreenState
    extends ConsumerState<PersonalDocumentUploadScreen> {
  bool _checkingExisting = true;
  bool _alreadySubmitted = false;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    final result = await ref.read(verificationRepositoryProvider).listMine();
    if (!mounted) return;
    result.when(
      success: (records) {
        final hasOne = records.any((r) => r.documentType == 'personal_document');
        if (hasOne) {
          setState(() => _alreadySubmitted = true);
          _continue();
        } else {
          setState(() => _checkingExisting = false);
        }
      },
      failure: (_) {
        // Couldn't confirm either way — fall back to showing the
        // (mandatory) upload step rather than silently skipping it.
        setState(() => _checkingExisting = false);
      },
    );
  }

  void _continue() {
    if (!mounted) return;
    context.go(AppRoutes.hobbies);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingExisting || _alreadySubmitted) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: context.colors.accent)),
      );
    }

    final state = ref.watch(personalDocumentControllerProvider);
    final controller = ref.read(personalDocumentControllerProvider.notifier);
    final isBusy = state.status == PersonalDocumentStatus.picking ||
        state.status == PersonalDocumentStatus.uploading;
    final isSuccess = state.status == PersonalDocumentStatus.success;

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    isSuccess ? Icons.check_circle_rounded : Icons.description_outlined,
                    size: 48,
                    color: isSuccess ? context.colors.success : context.colors.accent,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Upload a Personal Document', style: context.textStyles.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Upload a personal document (ID, certificate, etc.) as a photo or PDF — '
                'required to continue. It will be reviewed by our team; this may take a '
                'little time.',
                style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (state.pickedFilename != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.colors.line),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined, color: context.colors.muted),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          state.pickedFilename!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodyMedium,
                        ),
                      ),
                      if (isSuccess)
                        Icon(Icons.check_circle_rounded, color: context.colors.success, size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (state.status == PersonalDocumentStatus.error && state.failure != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: context.colors.danger, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          state.failure!.message,
                          style: context.textStyles.bodySmall?.copyWith(color: context.colors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              const Spacer(),
              if (!isSuccess) ...[
                PrimaryButton(
                  label: 'Choose from Gallery',
                  loading: isBusy,
                  onPressed: isBusy ? null : controller.pickAndUploadFromGallery,
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: isBusy ? null : controller.pickAndUploadPdf,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Upload PDF'),
                  ),
                ),
              ] else
                PrimaryButton(label: 'Continue', onPressed: _continue),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This step is required — there is no skip option.',
                textAlign: TextAlign.center,
                style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
