import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? trailingIcon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    // Full width is this widget's own contract (it's the app's bottom-
    // of-form CTA), not something it should inherit implicitly from the
    // theme's button default — see app_theme.dart's ElevatedButtonTheme
    // comment for why that default no longer forces infinite width on
    // every button app-wide.
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Flexible + ellipsis rather than letting the label size
                // itself unbounded — a long label (or a squeezed parent,
                // e.g. this button sharing a row with several icon
                // buttons) otherwise overflows the button's render box
                // instead of just truncating.
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Icon(trailingIcon, size: 18),
                ],
              ],
            ),
      ),
    );
  }
}
