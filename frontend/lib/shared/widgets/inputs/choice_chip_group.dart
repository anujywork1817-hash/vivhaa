import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ChoiceChipGroup<T> extends StatelessWidget {
  final String? label;
  final List<T> options;
  final String Function(T) labelBuilder;
  final Set<T> selected;
  final ValueChanged<T> onToggle;
  final bool singleSelect;

  const ChoiceChipGroup({
    super.key,
    this.label,
    required this.options,
    required this.labelBuilder,
    required this.selected,
    required this.onToggle,
    this.singleSelect = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: context.textStyles.titleSmall),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = selected.contains(option);
            return ChoiceChip(
              label: Text(labelBuilder(option)),
              selected: isSelected,
              onSelected: (_) => onToggle(option),
              labelStyle: TextStyle(
                color: isSelected ? context.colors.accent : context.colors.ink,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(color: isSelected ? context.colors.accent : context.colors.line),
            );
          }).toList(),
        ),
      ],
    );
  }
}
