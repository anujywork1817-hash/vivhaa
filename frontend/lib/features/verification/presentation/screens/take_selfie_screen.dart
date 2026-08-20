import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../controllers/selfie_controller.dart';

const _tips = [
  (icon: Icons.wb_sunny_outlined, label: 'Ensure Good Lighting in Background'),
  (icon: Icons.no_flash_rounded, label: 'Avoid Wearing Glasses'),
  (icon: Icons.block_rounded, label: 'Avoid Background Objects'),
  (icon: Icons.block_rounded, label: 'Avoid Wearing Hats'),
];

/// Liveness-capture instructions. The actual capture uses the device
/// camera via image_picker rather than a custom live preview — there's
/// no `camera` package in this project, so the oval face-guide overlay
/// from the reference isn't reproduced pixel-for-pixel.
class TakeSelfieScreen extends ConsumerStatefulWidget {
  const TakeSelfieScreen({super.key});

  @override
  ConsumerState<TakeSelfieScreen> createState() => _TakeSelfieScreenState();
}

class _TakeSelfieScreenState extends ConsumerState<TakeSelfieScreen> {
  bool _consent = true;

  Future<void> _capture() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front);
      if (picked == null) return;
      ref.read(selfiePathProvider.notifier).state = picked.path;
      if (mounted) context.push(AppRoutes.confirmSelfie);
    } catch (_) {
      // Camera unavailable on this platform/simulator — non-fatal for the demo.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          border: Border.all(color: context.colors.accent, width: 2),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        child: Icon(Icons.person_rounded, size: 48, color: context.colors.accent),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Take a Selfie', style: context.textStyles.headlineMedium),
                    const SizedBox(height: 6),
                    Text('Take a selfie to verify your identity.',
                        style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted)),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.colors.line),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Column(
                        children: _tips
                            .map((t) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(t.icon, size: 20, color: context.colors.muted),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(
                                          child:
                                              Text(t.label, style: context.textStyles.bodyMedium)),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                children: [
                  InkWell(
                    onTap: () => setState(() => _consent = !_consent),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                            value: _consent, onChanged: (v) => setState(() => _consent = v ?? false)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'I consent to Bureau to process and store my biometric data to verify my identity and prevent fraud.',
                              style: context.textStyles.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(label: 'Capture', onPressed: _consent ? _capture : null),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text('Powered By Bureau',
                        style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
