import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

class OtpInputField extends StatefulWidget {
  final int length;
  final ValueChanged<String> onCompleted;

  const OtpInputField({super.key, this.length = 6, required this.onCompleted});

  @override
  State<OtpInputField> createState() => _OtpInputFieldState();
}

class _OtpInputFieldState extends State<OtpInputField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    if (value.isNotEmpty && index < widget.length - 1) {
      _nodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _nodes[index - 1].requestFocus();
    }
    final code = _controllers.map((c) => c.text).join();
    if (code.length == widget.length) {
      FocusScope.of(context).unfocus();
      widget.onCompleted(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Boxes are flexed (not fixed-width) so all `length` boxes plus their
    // gaps always sum to exactly the available row width, regardless of
    // screen size — a fixed per-box width (the previous approach) doesn't
    // shrink for narrower devices and overflows the row.
    return Row(
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _otpBox(context, i)),
        ],
      ],
    );
  }

  Widget _otpBox(BuildContext context, int i) {
    return SizedBox(
      height: 60,
      child: TextField(
        controller: _controllers[i],
        focusNode: _nodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        // Built standalone (not derived from a themed text style) so
        // no display-font fallback chain can leak in — this field
        // only ever needs to render plain, unambiguous digits.
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Courier New', 'monospace'],
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: context.colors.ink,
          fontFeatures: const [
            FontFeature.liningFigures(),
            FontFeature.tabularFigures(),
          ],
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: context.colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: context.colors.accent, width: 1.6),
          ),
        ),
        onChanged: (v) => _onChanged(i, v),
      ),
    );
  }
}
