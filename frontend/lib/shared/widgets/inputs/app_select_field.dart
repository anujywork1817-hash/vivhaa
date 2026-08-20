import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// A tappable field that opens a bottom sheet list — the pattern this app
/// uses everywhere a native picker would otherwise be a plain dropdown
/// (religion, education, community, etc).
class AppSelectField extends StatelessWidget {
  final String label;
  final String? value;
  final String hint;
  final List<String> options;
  final ValueChanged<String> onSelected;

  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.hint = 'Select',
  });

  Future<void> _open(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: sheetContext.colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(label, style: sheetContext.textStyles.headlineSmall),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final option = options[i];
                  final isSelected = option == value;
                  return ListTile(
                    title: Text(option),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: sheetContext.colors.accent)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(option),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    // Label floats inside the border (floatingLabelBehavior: always in the
    // theme) rather than sitting above the field, matching AppTextField.
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  color: value == null ? context.colors.muted : context.colors.ink,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}
