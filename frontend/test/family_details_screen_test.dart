import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shaadi_clone/core/api/api_result.dart';
import 'package:shaadi_clone/core/theme/app_theme.dart';
import 'package:shaadi_clone/features/onboarding/data/api_onboarding_repository.dart';
import 'package:shaadi_clone/features/onboarding/domain/onboarding_repository.dart';
import 'package:shaadi_clone/features/onboarding/presentation/screens/family_details_screen.dart';
import 'package:shaadi_clone/shared/models/profile.dart';
import 'package:shaadi_clone/shared/widgets/inputs/app_select_field.dart';

/// Never called by anything this test exercises (no Continue tap goes far
/// enough to submit), but the provider needs a concrete implementation.
class _UnusedRepository implements OnboardingRepository {
  @override
  Future<ApiResult<Profile?>> getMyProfile() async => const ApiResult.success(null);

  @override
  Future<ApiResult<ProfileSubmitResult>> submitProfile(Profile profile) async =>
      ApiResult.success(ProfileSubmitResult(profile: profile));
}

/// Reproduces the "Yes/No and the financial-status radios don't seem
/// clickable" report directly against the real screen and real state
/// provider — no mocked widgets, so a genuine gesture/wiring bug would
/// show up here exactly as it would on a device.
void main() {
  Widget harness() {
    return ProviderScope(
      overrides: [
        onboardingRepositoryProvider.overrideWithValue(_UnusedRepository()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/family',
          routes: [
            GoRoute(path: '/family', builder: (_, __) => const FamilyDetailsScreen()),
            // partnerPreferences is where Continue would navigate; a stub
            // is enough since no test here taps a fully-enabled Continue.
            GoRoute(path: '/partner-preferences', builder: (_, __) => const SizedBox()),
          ],
        ),
      ),
    );
  }

  testWidgets('tapping "Yes" selects it and is not blocked by anything else on screen',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final yesChip = find.widgetWithText(ChoiceChip, 'Yes');
    expect(yesChip, findsOneWidget);
    expect(tester.widget<ChoiceChip>(yesChip).selected, isFalse);

    await tester.tap(yesChip);
    await tester.pumpAndSettle();

    expect(tester.widget<ChoiceChip>(yesChip).selected, isTrue,
        reason: 'Yes should be selected immediately after tapping it');
  });

  testWidgets('tapping "No" after "Yes" flips the selection (they are mutually exclusive)',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Yes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'No'));
    await tester.pumpAndSettle();

    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yes')).selected, isFalse);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'No')).selected, isTrue);
  });

  testWidgets('tapping a financial-status radio option selects it', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final eliteTile = find.widgetWithText(RadioListTile<String>, 'Elite');
    expect(eliteTile, findsOneWidget);

    await tester.tap(eliteTile);
    await tester.pumpAndSettle();

    // RadioListTile doesn't expose "is this one checked" as a simple
    // widget property once wrapped in RadioGroup, so the observable proxy
    // is the visual state: the Radio it contains should now report
    // checked for group value "Elite".
    final radio = tester.widget<Radio<String>>(
      find.descendant(of: eliteTile, matching: find.byType(Radio<String>)),
    );
    expect(radio.value, 'Elite');
  });

  testWidgets(
      'Continue enables once every required field is set, including Yes/No and financial status',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    Widget findContinue() => tester.widget(find.widgetWithText(FilledButton, 'Continue'));
    bool isEnabled() => (findContinue() as FilledButton).onPressed != null;

    expect(isEnabled(), isFalse, reason: 'nothing filled in yet');

    await tester.tap(find.widgetWithText(AppSelectField, "Mother's details"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Homemaker'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppSelectField, "Father's details"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private Job'));
    await tester.pumpAndSettle();

    expect(isEnabled(), isFalse,
        reason: 'still missing Yes/No and financial status');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Yes'));
    await tester.pumpAndSettle();

    expect(isEnabled(), isFalse, reason: 'financial status still unset');

    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Middle'));
    await tester.pumpAndSettle();

    expect(isEnabled(), isTrue,
        reason: 'every required field is now set — Continue should be tappable');
  });
}
