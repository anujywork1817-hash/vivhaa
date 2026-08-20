import 'package:flutter/material.dart';

/// A `Text` that always truncates instead of overflowing — the default
/// choice for any variable-length string (names, cities, occupations,
/// message previews, plan names, ...) so a long value degrades to an
/// ellipsis instead of a RenderFlex overflow. Use this in place of a raw
/// `Text(...)` whenever the string isn't a short, fixed label you fully
/// control (see `README_LAYOUT.md` in `lib/core/`).
class TruncatedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  const TruncatedText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
