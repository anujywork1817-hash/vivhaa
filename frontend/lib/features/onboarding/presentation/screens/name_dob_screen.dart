import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/inputs/app_date_picker_field.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../../../authentication/data/api_auth_repository.dart';
import '../controllers/profile_creation_controller.dart';

/// Matrimony sign-ups are adults only, and the partner-preference sliders
/// elsewhere already clamp to 18–65 — so 18 is the floor here too. The upper
/// bound just keeps the year grid to a sane length.
const minSignupAge = 18;
const maxSignupAge = 100;

/// First form step right after "This Profile is for" — just name and date
/// of birth, kept on their own screen rather than folded into the longer
/// basic-details step.
class NameDobScreen extends ConsumerStatefulWidget {
  const NameDobScreen({super.key});

  @override
  ConsumerState<NameDobScreen> createState() => _NameDobScreenState();
}

class _NameDobScreenState extends ConsumerState<NameDobScreen> {
  late final _firstNameController = TextEditingController(
      text: ref.read(profileCreationControllerProvider).draft.firstName);
  late final _lastNameController = TextEditingController(
      text: ref.read(profileCreationControllerProvider).draft.lastName);
  final _phoneController = TextEditingController();

  // Phone lives on the account (users.phone), not the profile draft — see
  // AuthRepository.requestLinkPhoneOtp/confirmLinkPhone — so unlike name/
  // DOB it isn't tracked in profileCreationControllerProvider. Tracks
  // whether the number currently in the field has actually been verified
  // this session, so re-showing this screen (e.g. via back navigation)
  // doesn't silently treat a since-edited number as already confirmed.
  bool _phoneVerified = false;
  bool _linkingPhone = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Optional: a blank field just means "skip for now" (the same as never
  /// visiting Account Settings' own add-phone flow) — only verifies when
  /// there's actually a number to verify. Reuses the same request/verify
  /// OTP flow Account Settings uses, since the backend requires proof of
  /// ownership before attaching a number either way.
  Future<bool> _verifyPhoneIfNeeded() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || _phoneVerified) return true;

    setState(() => _linkingPhone = true);
    final requestResult = await ref.read(authRepositoryProvider).requestLinkPhoneOtp(phone);
    if (!mounted) return false;
    final requestFailure = requestResult.when(success: (_) => null, failure: (f) => f);
    if (requestFailure != null) {
      setState(() => _linkingPhone = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(requestFailure.message)));
      return false;
    }

    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter verification code'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(hintText: '6-digit code sent to $phone'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Skip')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(codeController.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    codeController.dispose();
    if (!mounted) return false;
    setState(() => _linkingPhone = false);
    if (code == null || code.isEmpty) return true; // skipped — continue without a phone

    final confirmResult = await ref.read(authRepositoryProvider).confirmLinkPhone(phone, code);
    if (!mounted) return false;
    return confirmResult.when(
      success: (_) {
        setState(() => _phoneVerified = true);
        return true;
      },
      failure: (f) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
        return false;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    final canContinue = (draft.firstName ?? '').trim().isNotEmpty &&
        (draft.lastName ?? '').trim().isNotEmpty &&
        draft.dateOfBirth != null;

    final profileFor = draft.profileFor ?? ProfileFor.myself;

    // Computed per build rather than cached in state so a session left open
    // across midnight can't offer a date that has since gone out of range.
    final today = DateTime.now();
    final oldestAllowed = DateTime(today.year - maxSignupAge, today.month, today.day);
    final youngestAllowed = DateTime(today.year - minSignupAge, today.month, today.day);

    return OnboardingStepScaffold(
      stepIndex: 1,
      stepCount: onboardingStepCount,
      title: '${profileFor.possessiveTitle} name',
      headerIcon: Icons.badge_rounded,
      loading: _linkingPhone,
      onContinue: canContinue
          ? () async {
              if (await _verifyPhoneIfNeeded() && mounted) {
                context.push(AppRoutes.religionCommunity);
              }
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'First name',
            controller: _firstNameController,
            onChanged: (v) => controller.update((p) => p.copyWith(firstName: v)),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Last name',
            controller: _lastNameController,
            onChanged: (v) => controller.update((p) => p.copyWith(lastName: v)),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Phone number', style: context.textStyles.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Optional — lets matches you\'re chatting with reach you by phone '
            'instead of just email.',
            style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Phone number',
            hint: '+919876543210',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() => _phoneVerified = false),
            suffixIcon: _phoneVerified
                ? Icon(Icons.check_circle_rounded, color: context.colors.success)
                : null,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Date of birth', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          AppDatePickerField(
            label: 'Date of birth',
            hint: 'Tap to pick a date',
            value: draft.dateOfBirth,
            firstDate: oldestAllowed,
            lastDate: youngestAllowed,
            onSelected: (date) => controller.update((p) => p.copyWith(dateOfBirth: date)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You must be at least $minSignupAge to create a profile.',
            style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
          ),
        ],
      ),
    );
  }
}
