import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/profile_photo.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/misc/app_file_image.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../../data/api_profile_photos_repository.dart';

/// Full photo management — add, delete, and pick which photo is the
/// profile picture. The backend has always allowed up to 6 photos per
/// profile, but there was no UI for any of it beyond setting a single
/// picture, so extra photos could be uploaded and then never seen or
/// removed.
const int _maxPhotos = 6;

class ManagePhotosScreen extends ConsumerStatefulWidget {
  const ManagePhotosScreen({super.key});

  @override
  ConsumerState<ManagePhotosScreen> createState() => _ManagePhotosScreenState();
}

class _ManagePhotosScreenState extends ConsumerState<ManagePhotosScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(myPhotosProvider);
    // Keep the profile draft (and so every avatar in the app) in step with
    // whatever the gallery just changed.
    await ref.read(profileCreationControllerProvider.notifier).loadExisting();
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text(message)));
  }

  Future<void> _add(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    } catch (_) {
      _report('Could not open the picker.');
      return;
    }
    if (picked == null) return;

    setState(() => _busy = true);
    final result =
        await ref.read(profilePhotosRepositoryProvider).upload(picked.path);
    await result.when(
      success: (_) async {
        await _refresh();
        _report('Photo added.');
      },
      failure: (f) async => _report(f.message),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _chooseSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) _add(source);
  }

  Future<void> _setPrimary(ProfilePhoto photo) async {
    if (photo.isPrimary) return;
    setState(() => _busy = true);
    final result =
        await ref.read(profilePhotosRepositoryProvider).setPrimary(photo.id);
    await result.when(
      success: (_) async {
        await _refresh();
        _report('Profile picture updated.');
      },
      failure: (f) async => _report(f.message),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(ProfilePhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: Text(photo.isPrimary
            ? 'This is your profile picture. Another photo will be shown instead.'
            : 'This photo will be removed from your profile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete',
                style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result =
        await ref.read(profilePhotosRepositoryProvider).delete(photo.id);
    await result.when(
      success: (_) async {
        await _refresh();
        _report('Photo deleted.');
      },
      failure: (f) async => _report(f.message),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myPhotosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Photos'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(
          failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
          onRetry: () => ref.invalidate(myPhotosProvider),
        ),
        data: (photos) {
          final canAdd = photos.length < _maxPhotos;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  photos.isEmpty
                      ? 'Add up to $_maxPhotos photos. Your first one becomes your profile picture.'
                      : 'Tap a photo to make it your profile picture. ${photos.length} of $_maxPhotos used.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.colors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  children: [
                    for (final photo in photos)
                      _PhotoTile(
                        photo: photo,
                        enabled: !_busy,
                        onTap: () => _setPrimary(photo),
                        onDelete: () => _delete(photo),
                      ),
                    if (canAdd) _AddTile(enabled: !_busy, onTap: _chooseSource),
                  ],
                ),
                if (!canAdd) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'You\'ve reached the $_maxPhotos photo limit. Delete one to add another.',
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.colors.muted),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final ProfilePhoto photo;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PhotoTile({
    required this.photo,
    required this.enabled,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: AppFileImage(
              path: photo.url,
              fit: BoxFit.cover,
              placeholder: Container(color: context.colors.surface),
            ),
          ),
        ),
        if (photo.isPrimary)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.colors.accent,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: const Text('PROFILE',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onDelete : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AddTile({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: enabled ? onTap : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: context.colors.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: context.colors.accent),
            const SizedBox(height: 4),
            Text('Add', style: context.textStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}
