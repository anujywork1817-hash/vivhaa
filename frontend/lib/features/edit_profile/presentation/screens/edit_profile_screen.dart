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
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';

const _maritalOptions = MaritalStatus.values;
const _dietOptions = DietType.values;

/// Lets a member edit the fields most worth changing after onboarding —
/// not every one of the ~40 profile fields, but the ones people actually
/// come back to update (about me, career, location, lifestyle). Saves via
/// the same [ProfileCreationController.submit] onboarding already uses,
/// which PUTs to `/profiles/me` once a profile exists.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _aboutMe;
  late final TextEditingController _height;
  late final TextEditingController _education;
  late final TextEditingController _profession;
  late final TextEditingController _company;
  late final TextEditingController _income;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _country;

  MaritalStatus? _maritalStatus;
  DietType? _diet;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _aboutMe = TextEditingController();
    _height = TextEditingController();
    _education = TextEditingController();
    _profession = TextEditingController();
    _company = TextEditingController();
    _income = TextEditingController();
    _city = TextEditingController();
    _state = TextEditingController();
    _country = TextEditingController();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    await ref.read(profileCreationControllerProvider.notifier).loadExisting();
    if (!mounted) return;
    final draft = ref.read(profileCreationControllerProvider).draft;
    setState(() {
      _aboutMe.text = draft.aboutMe ?? '';
      _height.text = draft.heightCm?.toString() ?? '';
      _education.text = draft.highestEducation ?? '';
      _profession.text = draft.profession ?? '';
      _company.text = draft.companyName ?? '';
      _income.text = draft.annualIncome ?? '';
      _city.text = draft.city ?? '';
      _state.text = draft.state ?? '';
      _country.text = draft.country ?? '';
      _maritalStatus = draft.maritalStatus;
      _diet = draft.diet;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _aboutMe.dispose();
    _height.dispose();
    _education.dispose();
    _profession.dispose();
    _company.dispose();
    _income.dispose();
    _city.dispose();
    _state.dispose();
    _country.dispose();
    super.dispose();
  }

  /// Picks a new profile photo and saves immediately — a photo change is
  /// its own action, so it shouldn't sit unsaved behind the form's Save
  /// button (and the upload has to happen server-side either way).
  Future<void> _pickPhoto(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open the picker.')));
      }
      return;
    }
    if (picked == null) return;

    setState(() => _saving = true);
    final controller = ref.read(profileCreationControllerProvider.notifier);
    controller.update((p) => p.copyWith(
          photoUrls: [...p.photoUrls, picked!.path],
          profilePhotoUrl: picked.path,
        ));
    final ok = await controller.submit();
    if (!mounted) return;
    setState(() => _saving = false);
    final photoFailures = ref.read(profileCreationControllerProvider).photoUploadFailures;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok && photoFailures == 0
          ? 'Profile photo updated.'
          : "Couldn't upload that photo. Please try again."),
    ));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = ref.read(profileCreationControllerProvider.notifier);
    controller.update((p) => p.copyWith(
          aboutMe: _aboutMe.text.trim(),
          heightCm: int.tryParse(_height.text.trim()),
          maritalStatus: _maritalStatus,
          diet: _diet,
          highestEducation: _education.text.trim(),
          profession: _profession.text.trim(),
          companyName: _company.text.trim(),
          annualIncome: _income.text.trim(),
          city: _city.text.trim(),
          state: _state.text.trim(),
          country: _country.text.trim(),
        ));
    final ok = await controller.submit();
    if (!mounted) return;
    setState(() => _saving = false);
    final photoFailures = ref.read(profileCreationControllerProvider).photoUploadFailures;
    final String message;
    if (!ok) {
      message = 'Could not save changes. Please try again.';
    } else if (photoFailures > 0) {
      message = photoFailures == 1
          ? "Profile updated, but the photo couldn't be uploaded. Please try adding it again."
          : "Profile updated, but $photoFailures photos couldn't be uploaded. Please try adding them again.";
    } else {
      message = 'Profile updated.';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    // Stay on the screen when a photo failed so the user can retry it
    // without navigating back in and re-picking from scratch.
    if (ok && photoFailures == 0) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: _ProfilePhotoPicker(onPick: _pickPhoto)),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.push(AppRoutes.managePhotos),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Manage all photos'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('About', style: context.textStyles.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _aboutMe,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Tell us about yourself'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Lifestyle', style: context.textStyles.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Height (cm)'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<MaritalStatus>(
                    initialValue: _maritalStatus,
                    decoration: const InputDecoration(labelText: 'Marital status'),
                    items: _maritalOptions
                        .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                        .toList(),
                    onChanged: (v) => setState(() => _maritalStatus = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<DietType>(
                    initialValue: _diet,
                    decoration: const InputDecoration(labelText: 'Diet'),
                    items: _dietOptions
                        .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                        .toList(),
                    onChanged: (v) => setState(() => _diet = v),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Education & career', style: context.textStyles.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _education,
                    decoration: const InputDecoration(labelText: 'Highest qualification'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _profession,
                    decoration: const InputDecoration(labelText: 'Profession'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _company,
                    decoration: const InputDecoration(labelText: 'Company'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _income,
                    decoration: const InputDecoration(labelText: 'Annual income'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Location', style: context.textStyles.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _state,
                    decoration: const InputDecoration(labelText: 'State'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _country,
                    decoration: const InputDecoration(labelText: 'Country'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(label: 'Save changes', loading: _saving, onPressed: _save),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
    );
  }
}

/// Current profile photo with a camera badge that opens a gallery/camera
/// chooser — the only way to change a photo after onboarding, which
/// previously had no post-onboarding entry point at all.
class _ProfilePhotoPicker extends ConsumerWidget {
  final ValueChanged<ImageSource> onPick;
  const _ProfilePhotoPicker({required this.onPick});

  Future<void> _chooseSource(BuildContext context) async {
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
    if (source != null) onPick(source);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final photo = draft.profilePhotoUrl;

    return Stack(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: context.colors.line, width: 1.4),
            color: context.colors.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: photo != null
              ? AppFileImage(path: photo, fit: BoxFit.cover)
              : Icon(Icons.person_outline_rounded, size: 60, color: context.colors.muted),
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _chooseSource(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.bg, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}
