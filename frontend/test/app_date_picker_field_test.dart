import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaadi_clone/core/theme/app_theme.dart';
import 'package:shaadi_clone/shared/widgets/inputs/app_date_picker_field.dart';

/// The date-of-birth calendar is bounded on both ends, and the bounds are the
/// whole point: a birthday one day short of 18 must not be reachable. These
/// drive the real widget rather than the range maths in isolation, because
/// the out-of-range days are still *rendered* — they're just not tappable,
/// and that distinction only exists at the widget layer.
void main() {
  // A fixed "today" so the expectations below don't drift with the clock.
  final today = DateTime(2026, 8, 20);
  final oldest = DateTime(today.year - 100, today.month, today.day);
  final youngest = DateTime(today.year - 18, today.month, today.day);

  Widget harness({
    DateTime? value,
    required ValueChanged<DateTime> onSelected,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: AppDatePickerField(
          label: 'Date of birth',
          value: value,
          firstDate: oldest,
          lastDate: youngest,
          onSelected: onSelected,
        ),
      ),
    );
  }

  testWidgets('shows the hint until a date is chosen', (tester) async {
    await tester.pumpWidget(harness(onSelected: (_) {}));
    expect(find.text('Select date'), findsOneWidget);

    await tester.pumpWidget(harness(value: DateTime(1996, 3, 12), onSelected: (_) {}));
    expect(find.text('Select date'), findsNothing);
    expect(find.text('12 March 1996'), findsOneWidget);
  });

  testWidgets('opens on the latest allowed month, not on today', (tester) async {
    await tester.pumpWidget(harness(onSelected: (_) {}));
    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();

    // youngest = August 2008, i.e. the 18th-birthday month.
    expect(find.text('August 2008'), findsOneWidget);
  });

  testWidgets('picking a day reports it only after Confirm', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(harness(
      value: DateTime(1996, 3, 12),
      onSelected: (d) => picked = d,
    ));

    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();
    expect(find.text('March 1996'), findsOneWidget);

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(picked, isNull, reason: 'tapping a day should not commit on its own');

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(1996, 3, 20));
  });

  testWidgets('Cancel reports nothing', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(harness(
      value: DateTime(1996, 3, 12),
      onSelected: (d) => picked = d,
    ));

    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(picked, isNull);
  });

  testWidgets('days past the 18-year cutoff are not selectable', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(harness(onSelected: (d) => picked = d));

    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();
    expect(find.text('August 2008'), findsOneWidget);

    // The 20th is exactly the 18th birthday — allowed.
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2008, 8, 20));

    // The 21st is a day too young — the cell renders but does nothing.
    picked = null;
    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2008, 8, 20), reason: 'selection should not have moved');
  });

  testWidgets('cannot page past the youngest allowed month', (tester) async {
    await tester.pumpWidget(harness(onSelected: (_) {}));
    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('August 2008'), findsOneWidget,
        reason: 'September 2008 is entirely out of range');

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('July 2008'), findsOneWidget);
  });

  testWidgets('header drills down through years and months to days', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(harness(onSelected: (d) => picked = d));

    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();

    // Days -> years.
    await tester.tap(find.text('August 2008'));
    await tester.pumpAndSettle();
    expect(find.text('Select year'), findsOneWidget);

    // Years -> months.
    await tester.tap(find.text('2000'));
    await tester.pumpAndSettle();
    expect(find.text('2000'), findsWidgets);
    expect(find.text('Jan'), findsOneWidget);

    // Months -> days.
    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();
    expect(find.text('June 2000'), findsOneWidget);

    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2000, 6, 9));
  });

  testWidgets('February leap years render the right number of days', (tester) async {
    await tester.pumpWidget(harness(value: DateTime(2000, 2, 1), onSelected: (_) {}));
    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();

    expect(find.text('February 2000'), findsOneWidget);
    expect(find.text('29'), findsOneWidget, reason: '2000 is a leap year');
    expect(find.text('30'), findsNothing);

    // 1999 is not: February must stop at 28.
    await tester.tap(find.byType(AppDatePickerField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('February 2000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1999'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feb'));
    await tester.pumpAndSettle();
    expect(find.text('February 1999'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('29'), findsNothing);
  });
}
