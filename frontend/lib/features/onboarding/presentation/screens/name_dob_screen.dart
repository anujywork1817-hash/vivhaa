import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/misc/onboarding_step_scaffold.dart';
import '../controllers/profile_creation_controller.dart';

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
  final _dayController = TextEditingController();
  final _monthController = TextEditingController();
  final _yearController = TextEditingController();

  final _dayFocus = FocusNode();
  final _monthFocus = FocusNode();
  final _yearFocus = FocusNode();

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    _dayFocus.dispose();
    _monthFocus.dispose();
    _yearFocus.dispose();
    super.dispose();
  }

  void _tryUpdateDateOfBirth(void Function(DateTime? date) apply) {
    final day = int.tryParse(_dayController.text);
    final month = int.tryParse(_monthController.text);
    final year = int.tryParse(_yearController.text);
    if (day == null || month == null || year == null || _yearController.text.length != 4) {
      apply(null);
      return;
    }
    if (day < 1 || day > 31 || month < 1 || month > 12) {
      apply(null);
      return;
    }
    final date = DateTime(year, month, day);
    // Guard against overflow dates (e.g. 31 Feb rolling into March).
    if (date.month != month) {
      apply(null);
      return;
    }
    apply(date);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;

    final canContinue = (draft.firstName ?? '').trim().isNotEmpty &&
        (draft.lastName ?? '').trim().isNotEmpty &&
        draft.dateOfBirth != null;

    final profileFor = draft.profileFor ?? ProfileFor.myself;

    return OnboardingStepScaffold(
      stepIndex: 1,
      stepCount: onboardingStepCount,
      title: '${profileFor.possessiveTitle} name',
      headerIcon: Icons.badge_rounded,
      onContinue: canContinue ? () => context.push(AppRoutes.religionCommunity) : null,
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
          Text('Date of birth', style: context.textStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Day',
                  hint: 'DD',
                  controller: _dayController,
                  focusNode: _dayFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  onChanged: (v) {
                    _tryUpdateDateOfBirth(
                        (date) => controller.update((p) => p.copyWith(dateOfBirth: date)));
                    if (v.length == 2) FocusScope.of(context).requestFocus(_monthFocus);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppTextField(
                  label: 'Month',
                  hint: 'MM',
                  controller: _monthController,
                  focusNode: _monthFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  onChanged: (v) {
                    _tryUpdateDateOfBirth(
                        (date) => controller.update((p) => p.copyWith(dateOfBirth: date)));
                    if (v.length == 2) FocusScope.of(context).requestFocus(_yearFocus);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: AppTextField(
                  label: 'Year',
                  hint: 'YYYY',
                  controller: _yearController,
                  focusNode: _yearFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (_) => _tryUpdateDateOfBirth(
                      (date) => controller.update((p) => p.copyWith(dateOfBirth: date))),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
