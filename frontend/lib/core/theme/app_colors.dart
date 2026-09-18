import 'package:flutter/material.dart';

/// Brand palette for the app — a premium Indian matrimonial aesthetic:
/// warm off-white ground, rose primary, rose-gold for premium accents.
/// Every value here is one of the design system's approved hex values —
/// resist adding new colors; derive tints/shades from these instead.
class AppColors {
  AppColors._();

  // Light
  static const Color bgLight = Color(0xFFFFF8F6);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color inkLight = Color(0xFF1F2937);
  static const Color mutedLight = Color(0xFF6B7280);
  static const Color lineLight = Color(0xFFE5E7EB);

  // Very light gray for subtle secondary surfaces (e.g. a card-on-card
  // background) — distinct from surfaceLight/white. Not wired into any
  // ThemeData slot yet since nothing currently calls for a second surface
  // tier; available for screens that want it.
  static const Color surfaceSubtleLight = Color(0xFFF7F7F7);

  // Dark — true black instead of the maroon-tinted black this used to be
  // (0xFF1D1013 reads as "dark red" at a glance, not "dark theme"). Surface
  // one step up from pure black (not 0x000000 itself) so cards/sheets are
  // still visibly distinct from the page background.
  static const Color bgDark = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color inkDark = Color(0xFFF2F2F2);
  static const Color mutedDark = Color(0xFF9E9E9E);
  static const Color lineDark = Color(0xFF2A2A2A);

  // Brand — shared across themes
  static const Color accent = Color(0xFFD9467E); // Primary Rose
  static const Color accentDark = Color(0xFFD9467E);
  // Pale tint of the primary rose — selected-chip backgrounds, soft
  // highlights. Not one of the five named hexes in the design system, but
  // derived directly from Primary Rose rather than an unrelated color.
  static const Color accentSoftLight = Color(0xFFFBE4EC);
  static const Color accentSoftDark = Color(0xFF53202C);
  // Dark Rose — headings/emphasis per the design system, and doubles as
  // the pressed/active variant of the primary rose (wired into button
  // pressed states in app_theme.dart).
  static const Color accentPressed = Color(0xFF8B1E4A);
  // Rose Gold — premium labels, subtle highlights, special badges.
  static const Color gold = Color(0xFFE9A178);
  static const Color goldDark = Color(0xFFD8A855);

  static const Color success = Color(0xFF2E7D4F);
  static const Color warning = Color(0xFFB8863C);
  static const Color danger = Color(0xFFE64A19);
  static const Color onAccent = Color(0xFFFFFFFF);

  // Kept for the few screens still using a gradient background (Premium,
  // welcome/splash) — updated to the rose palette. The design system
  // says to avoid gradients as a *default* card/button treatment, which
  // the redesigned components below don't use; these two are pre-existing
  // hero treatments, not something Phase 1 introduces.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD9467E), Color(0xFF8B1E4A)],
  );

  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE9A178), Color(0xFF8B1E4A)],
  );
}
