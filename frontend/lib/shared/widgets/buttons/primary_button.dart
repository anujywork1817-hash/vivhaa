import 'package:flutter/material.dart';

class PrimaryButton extends StatefulWidget {
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
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || widget.loading) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Full width is this widget's own contract (it's the app's bottom-
    // of-form CTA), not something it should inherit implicitly from the
    // theme's button default — see app_theme.dart's ElevatedButtonTheme
    // comment for why that default no longer forces infinite width on
    // every button app-wide.
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        // A small press-in scale is what makes a flat, code-drawn button
        // read as tactile/modern rather than a static rectangle — cheap to
        // add here since every CTA in the app routes through this widget.
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: widget.loading ? null : widget.onPressed,
            child: widget.loading
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
                        child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (widget.trailingIcon != null) ...[
                        const SizedBox(width: 8),
                        Icon(widget.trailingIcon, size: 18),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
