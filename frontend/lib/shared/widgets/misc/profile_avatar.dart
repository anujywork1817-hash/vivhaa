import 'package:flutter/material.dart';
import 'app_file_image.dart';

/// A member's photo when there is one ([photoUrl]), otherwise a
/// deterministic placeholder — a pastel tint derived from the name plus
/// their initials. The placeholder also covers the moments a real photo
/// can't be shown: while it loads, or if the fetch fails.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final double size;
  final BorderRadius? borderRadius;

  /// Local file path or remote URL; see [AppFileImage].
  final String? photoUrl;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.size = 56,
    this.borderRadius,
    this.photoUrl,
  });

  static const _palette = [
    Color(0xFFE7B8A6), Color(0xFFC9D6B8), Color(0xFFB9CDE5),
    Color(0xFFE3C6E0), Color(0xFFE8D3A6), Color(0xFFA9D3CB),
  ];

  @override
  Widget build(BuildContext context) {
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    final color = _palette[hash % _palette.length];
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();

    // Callers pass size: double.infinity to mean "fill the parent". Doing
    // arithmetic on that yields Infinity, and an infinite fontSize throws
    // in PlatformDispatcher.scaleFontSize during layout — which leaves the
    // render object with no size, so anything drawn here also stops being
    // hit-testable (scrolling over a full-bleed avatar silently died).
    // Sizes are therefore only derived when finite, and infinite extents
    // are passed through as null so the parent's constraints apply.
    final hasFiniteSize = size.isFinite;
    final boxSize = hasFiniteSize ? size : null;
    final radius = borderRadius ?? BorderRadius.circular(hasFiniteSize ? size / 2 : 0);
    final initialsSize = hasFiniteSize ? size * 0.36 : 48.0;

    final placeholder = Container(
      width: boxSize,
      height: boxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initials,
          style: TextStyle(
            fontSize: initialsSize,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF3A2A22),
          ),
        ),
      ),
    );

    if (photoUrl == null || photoUrl!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: boxSize,
        height: boxSize,
        child: AppFileImage(
          path: photoUrl!,
          fit: BoxFit.cover,
          width: boxSize,
          height: boxSize,
          placeholder: placeholder,
        ),
      ),
    );
  }
}
