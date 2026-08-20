import 'dart:ui';
import 'package:flutter/material.dart';
import 'profile_avatar.dart';

/// The frosted-glass "photo hidden until connected" state — a real blur
/// (`ImageFiltered`, not a translucent overlay pretending to be one)
/// applied over the underlying avatar, with a lock icon and explanation
/// centered on top, matching members who restrict photo visibility.
class LockedProfilePhoto extends StatelessWidget {
  final String name;
  final String pronoun;
  final BorderRadius? borderRadius;

  const LockedProfilePhoto({
    super.key,
    required this.name,
    this.pronoun = 'their',
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A real blur is a genuinely expensive GPU pass, and this shows
          // up in scrolling lists (Home's recommended-matches row, the
          // Matches deck) where several can be composited at once. A
          // lower sigma is cheaper to render and still reads as "hidden
          // photo" at the size these actually display at.
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10, tileMode: TileMode.decal),
              child: ProfileAvatar(name: name, size: double.infinity, borderRadius: BorderRadius.zero),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.32)),
          // Sized via LayoutBuilder rather than a fixed layout: this widget
          // is reused both as a full profile-card photo (room for the
          // explanation sentence) and as a small ~72px avatar (e.g. the
          // Matches grid card's locked-photo state), where the sentence
          // has nowhere near enough room and would overflow the circle.
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 120 || constraints.maxWidth < 120;
              return Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: compact ? 28 : 40,
                        height: compact ? 28 : 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_rounded,
                            color: Colors.white, size: compact ? 14 : 20),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${name.split(' ').first} has chosen to show $pronoun Photo only to Members $pronoun is connected to',
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
