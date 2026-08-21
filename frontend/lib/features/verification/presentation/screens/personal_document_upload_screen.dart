import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../data/api_verification_repository.dart';
import '../controllers/personal_document_controller.dart';

/// Mandatory onboarding step, shown right after selfie verification: the
/// user must submit at least one supporting personal document (Aadhaar
/// and/or PAN, each optional individually, either as a photo or a PDF)
/// for admin review before continuing. There is no skip — if the user has
/// already submitted at least one (checked via [VerificationRepository.
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

  static const _acceptedTypes = {'aadhaar', 'pan'};

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
        final hasOne = records.any((r) => _acceptedTypes.contains(r.documentType));
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

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
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
                    Icons.description_outlined,
                    size: 48,
                    color: context.colors.accent,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Verify Your Identity', style: context.textStyles.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Upload your Aadhaar card and/or PAN card as a photo or PDF. Each is '
                'optional, but you must submit at least one to continue. Documents are '
                'reviewed by our team; this may take a little time.',
                style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),
              _DocumentCard(
                kind: PersonalDocumentKind.aadhaar,
                slot: state.aadhaar,
                onPickGallery: () => controller.pickAndUploadFromGallery(PersonalDocumentKind.aadhaar),
                onPickPdf: () => controller.pickAndUploadPdf(PersonalDocumentKind.aadhaar),
              ),
              const SizedBox(height: AppSpacing.md),
              _DocumentCard(
                kind: PersonalDocumentKind.pan,
                slot: state.pan,
                onPickGallery: () => controller.pickAndUploadFromGallery(PersonalDocumentKind.pan),
                onPickPdf: () => controller.pickAndUploadPdf(PersonalDocumentKind.pan),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Continue',
                onPressed: state.hasAtLeastOne ? _continue : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                state.hasAtLeastOne
                    ? 'You can add the other document later from your profile.'
                    : 'Submit at least one document to continue — there is no skip option.',
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

class _DocumentCard extends StatelessWidget {
  final PersonalDocumentKind kind;
  final PersonalDocumentSlotState slot;
  final VoidCallback onPickGallery;
  final VoidCallback onPickPdf;

  const _DocumentCard({
    required this.kind,
    required this.slot,
    required this.onPickGallery,
    required this.onPickPdf,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy = slot.status == PersonalDocumentStatus.picking ||
        slot.status == PersonalDocumentStatus.uploading;
    final isSuccess = slot.status == PersonalDocumentStatus.success;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: isSuccess ? context.colors.success : context.colors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(kind.label, style: context.textStyles.bodyLarge),
              ),
              Text(
                'Optional',
                style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
              ),
              if (isSuccess) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.check_circle_rounded, color: context.colors.success, size: 20),
              ],
            ],
          ),
          if (slot.pickedFilename != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 16, color: context.colors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    slot.pickedFilename!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (slot.status == PersonalDocumentStatus.error && slot.failure != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              slot.failure!.message,
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.danger),
            ),
          ],
          if (!isSuccess) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isBusy ? null : onPickGallery,
                    child: isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: isBusy ? null : onPickPdf,
                    child: const Text('Upload PDF'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
