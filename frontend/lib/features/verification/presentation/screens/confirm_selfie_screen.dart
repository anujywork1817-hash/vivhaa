import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/misc/app_file_image.dart';
import '../controllers/selfie_controller.dart';

class ConfirmSelfieScreen extends ConsumerWidget {
  const ConfirmSelfieScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(selfiePathProvider);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: path != null
                ? AppFileImage(path: path, width: double.infinity, fit: BoxFit.cover)
                : ColoredBox(color: context.colors.line),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Please Confirm the Following', style: context.textStyles.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                _CheckRow(icon: Icons.face_retouching_natural_rounded, label: 'Face is clearly visible, & the image is not blurry.'),
                _CheckRow(icon: Icons.image_not_supported_outlined, label: 'There is no other object in the background'),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: 'Continue',
                        onPressed: () => context.push(AppRoutes.verifying),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text('Powered By Bureau',
                      style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CheckRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.colors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: context.textStyles.bodySmall)),
        ],
      ),
    );
  }
}
