import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// A tappable field that opens a full calendar in a bottom sheet — the same
/// pattern as [AppSelectField], but for dates. Used for date of birth, where
/// the range is bounded by a minimum/maximum age rather than free-form.
class AppDatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String hint;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onSelected;

  const AppDatePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onSelected,
    this.hint = 'Select date',
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CalendarSheet(
        label: label,
        initialDate: value,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? hint : formatDate(value!),
                style: TextStyle(
                  color: value == null ? context.colors.muted : context.colors.ink,
                ),
              ),
            ),
            Icon(Icons.calendar_month_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// `12 March 1996` — how the app shows a date to people. The API format
/// (`yyyy-MM-dd`) is handled at the repository boundary instead.
String formatDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// Which grid the sheet is showing. Tapping the header title jumps straight
/// to years, so a birth year 30 years back is two taps away rather than 360
/// swipes through months.
enum _CalendarView { days, months, years }

class _CalendarSheet extends StatefulWidget {
  final String label;
  final DateTime? initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _CalendarSheet({
    required this.label,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  static const _gridHeight = 280.0;

  late DateTime _visibleMonth;
  DateTime? _selected;
  _CalendarView _view = _CalendarView.days;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    // Open on the selected date's month, or on the latest allowed month — for
    // a date of birth that is the "youngest permitted" end, a far better
    // starting point than today.
    final anchor = widget.initialDate ?? widget.lastDate;
    _visibleMonth = DateTime(anchor.year, anchor.month);
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInRange(DateTime d) =>
      !d.isBefore(_dayOnly(widget.firstDate)) && !d.isAfter(_dayOnly(widget.lastDate));

  /// True when [month] holds at least one day inside the allowed range. This
  /// is what greys out the arrows and the out-of-range month/year cells at
  /// the two ends.
  bool _monthHasSelectableDay(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final lastOfMonth = DateTime(month.year, month.month + 1, 0);
    return !firstOfMonth.isAfter(_dayOnly(widget.lastDate)) &&
        !lastOfMonth.isBefore(_dayOnly(widget.firstDate));
  }

  void _stepMonth(int delta) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    if (!_monthHasSelectableDay(next)) return;
    setState(() => _visibleMonth = next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(widget.label, style: context.textStyles.headlineSmall),
            ),
            _buildHeader(context),
            const SizedBox(height: AppSpacing.md),
            // A fixed height stops the sheet jumping as the user moves between
            // a 5-row and a 6-row month, or switches to the year grid.
            SizedBox(height: _gridHeight, child: _buildBody(context)),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _selected == null ? null : () => Navigator.of(context).pop(_selected),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final title = switch (_view) {
      _CalendarView.days => '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
      _CalendarView.months => '${_visibleMonth.year}',
      _CalendarView.years => 'Select year',
    };

    final onDays = _view == _CalendarView.days;
    final canStepBack = onDays &&
        _monthHasSelectableDay(DateTime(_visibleMonth.year, _visibleMonth.month - 1));
    final canStepForward = onDays &&
        _monthHasSelectableDay(DateTime(_visibleMonth.year, _visibleMonth.month + 1));

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () => setState(
                () => _view = onDays ? _CalendarView.years : _CalendarView.days),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: context.textStyles.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    onDays ? Icons.arrow_drop_down_rounded : Icons.arrow_drop_up_rounded,
                    color: context.colors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: canStepBack ? () => _stepMonth(-1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous month',
        ),
        IconButton(
          onPressed: canStepForward ? () => _stepMonth(1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next month',
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) => switch (_view) {
        _CalendarView.days => _buildDayGrid(context),
        _CalendarView.months => _buildMonthGrid(context),
        _CalendarView.years => _buildYearGrid(context),
      };

  Widget _buildDayGrid(BuildContext context) {
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // DateTime.weekday is 1=Mon..7=Sun and the grid starts on Monday, so the
    // number of leading blank cells is weekday - 1.
    final leadingBlanks = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday - 1;

    return Column(
      children: [
        Row(
          children: [
            for (final initial in _weekdayInitials)
              Expanded(
                child: Center(
                  child: Text(
                    initial,
                    style: context.textStyles.labelSmall
                        ?.copyWith(color: context.colors.muted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: AppSpacing.xs,
              crossAxisSpacing: AppSpacing.xs,
            ),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (_, i) {
              if (i < leadingBlanks) return const SizedBox.shrink();
              final day = i - leadingBlanks + 1;
              final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
              final selectable = _isInRange(date);

              return _CalendarCell(
                label: '$day',
                isSelected: _selected != null && _isSameDay(date, _selected!),
                isEnabled: selectable,
                onTap: selectable ? () => setState(() => _selected = date) : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthGrid(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 2.2,
      ),
      itemCount: 12,
      itemBuilder: (_, i) {
        final month = DateTime(_visibleMonth.year, i + 1);
        final selectable = _monthHasSelectableDay(month);
        return _CalendarCell(
          label: _monthNames[i].substring(0, 3),
          isSelected: _visibleMonth.month == i + 1,
          isEnabled: selectable,
          onTap: selectable
              ? () => setState(() {
                    _visibleMonth = month;
                    _view = _CalendarView.days;
                  })
              : null,
        );
      },
    );
  }

  Widget _buildYearGrid(BuildContext context) {
    final firstYear = widget.firstDate.year;
    final yearCount = widget.lastDate.year - firstYear + 1;

    return GridView.builder(
      padding: EdgeInsets.zero,
      controller: ScrollController(
        initialScrollOffset: _initialYearOffset(yearCount),
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 2.2,
      ),
      itemCount: yearCount,
      itemBuilder: (_, i) {
        final year = firstYear + i;
        return _CalendarCell(
          label: '$year',
          isSelected: _visibleMonth.year == year,
          isEnabled: true,
          onTap: () => setState(() {
            // Clamp the month so jumping to a boundary year cannot land on a
            // month that is entirely outside the range.
            var month = DateTime(year, _visibleMonth.month);
            if (!_monthHasSelectableDay(month)) {
              month = month.isBefore(_dayOnly(widget.firstDate))
                  ? DateTime(widget.firstDate.year, widget.firstDate.month)
                  : DateTime(widget.lastDate.year, widget.lastDate.month);
            }
            _visibleMonth = month;
            _view = _CalendarView.months;
          }),
        );
      },
    );
  }

  /// Opens the year grid near the year already in view rather than at the
  /// oldest year, which for a 1925 lower bound would otherwise be ~25 rows
  /// of scrolling away.
  double _initialYearOffset(int yearCount) {
    const rowHeight = 56.0;
    final row = ((_visibleMonth.year - widget.firstDate.year) / 3).floor();
    final maxOffset = ((yearCount / 3).ceil() * rowHeight) - _gridHeight;
    if (maxOffset <= 0) return 0;
    return (row * rowHeight - 100).clamp(0.0, maxOffset);
  }
}

class _CalendarCell extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _CalendarCell({
    required this.label,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color foreground;
    if (isSelected) {
      foreground = Colors.white;
    } else if (isEnabled) {
      foreground = context.colors.ink;
    } else {
      foreground = context.colors.muted.withValues(alpha: 0.4);
    }

    return Material(
      color: isSelected ? context.colors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: context.textStyles.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
