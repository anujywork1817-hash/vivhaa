import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light = _build(
    brightness: Brightness.light,
    bg: AppColors.bgLight,
    surface: AppColors.surfaceLight,
    surfaceSubtle: AppColors.surfaceSubtleLight,
    ink: AppColors.inkLight,
    muted: AppColors.mutedLight,
    line: AppColors.lineLight,
    accent: AppColors.accent,
    accentPressed: AppColors.accentPressed,
    accentSoft: AppColors.accentSoftLight,
  );

  static ThemeData dark = _build(
    brightness: Brightness.dark,
    bg: AppColors.bgDark,
    surface: AppColors.surfaceDark,
    surfaceSubtle: AppColors.surfaceDark,
    ink: AppColors.inkDark,
    muted: AppColors.mutedDark,
    line: AppColors.lineDark,
    accent: AppColors.accentDark,
    accentPressed: AppColors.accentPressed,
    accentSoft: AppColors.accentSoftDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfaceSubtle,
    required Color ink,
    required Color muted,
    required Color line,
    required Color accent,
    required Color accentPressed,
    required Color accentSoft,
  }) {
    final textTheme = AppTypography.textTheme(ink, muted);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: AppColors.onAccent,
        secondary: AppColors.gold,
        onSecondary: AppColors.onAccent,
        surface: surface,
        onSurface: ink,
        error: AppColors.danger,
        onError: AppColors.onAccent,
        surfaceContainerHighest: surfaceSubtle,
        outline: line,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: AppColors.onAccent,
          // Pressed/hover overlay uses the dark accent variant so the
          // button visibly deepens on press instead of just dimming.
          overlayColor: accentPressed,
          // Size.fromHeight(52) used to sit here — that's Size(double
          // .infinity, 52), so EVERY ElevatedButton defaulted to wanting
          // infinite width. Harmless inside a full-width slot (a form's
          // bottom CTA, an Expanded/Column-stretch context), but any
          // button placed directly in a Row without Expanded — an inline
          // "Unblock"/"Connect" action next to a list row — genuinely
          // got unbounded width from Flutter's layout and overflowed or
          // rendered oversized. That's the actual root cause behind the
          // pile of one-off `minimumSize: Size(0, 32)` overrides scattered
          // across screens: each was a local workaround for this global
          // default, not an unrelated touch-target bug. PrimaryButton
          // (the real full-width CTA wrapper) now owns its own width
          // explicitly instead of leaning on this.
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          overlayColor: accentSoft,
          minimumSize: const Size(64, 52),
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          textStyle: textTheme.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent, overlayColor: accentSoft),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 4),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 4),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 4),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 4),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        labelStyle: TextStyle(color: muted, fontSize: 13),
        floatingLabelStyle: TextStyle(color: muted, fontSize: 12.5),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.6)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accentSoft,
        side: BorderSide(color: line),
        labelStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill)),
      ),
      // GoRoute wraps every screen in a MaterialPage under the hood, so
      // this one setting is what actually controls the push/pop
      // animation for every route in app_router.dart — no need to touch
      // any of the 60+ GoRoute entries individually. Previously left
      // unset, which meant each platform's own OEM default applied
      // (Android's especially minimal "fade upwards" that barely reads
      // as an animation), and it differed device to device. The same
      // builder is used for every TargetPlatform so navigation feels
      // identical everywhere rather than depending on which OS the app
      // happens to be running on.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.windows: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.linux: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.fuchsia: _FadeSlidePageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1),
      // Follows the theme like every other surface: `surface` in light
      // mode (previously a fixed dark-black bar even under the light
      // theme, which read as a bug — a bright screen with a black bar
      // welded to the bottom of it), `surfaceDark` under dark mode. The
      // selected/unselected item colors already come from the per-theme
      // `accent`/`muted` passed into `_build`, so they keep readable
      // contrast against whichever background this resolves to.
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: line),
        ),
      ),
      // Floating + rounded + brand ink color instead of Flutter's plain
      // flush-black default bar — the "school project" look every one of
      // this app's 26 raw ScaffoldMessenger.showSnackBar call sites was
      // stuck with, since none of them set their own shape/behavior.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: bg),
        actionTextColor: accent,
        elevation: 4,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      extensions: [
        AppSemanticColors(
          bg: bg,
          surface: surface,
          surfaceSubtle: surfaceSubtle,
          ink: ink,
          muted: muted,
          line: line,
          accent: accent,
          accentPressed: accentPressed,
          accentSoft: accentSoft,
          gold: brightness == Brightness.light ? AppColors.gold : AppColors.goldDark,
          success: AppColors.success,
          warning: AppColors.warning,
          danger: AppColors.danger,
        ),
      ],
    );
  }
}

/// Theme extension so widgets can read tokens (e.g. `.accentSoft`) without
/// re-deriving light/dark branching everywhere.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color bg, surface, surfaceSubtle, ink, muted, line, accent, accentPressed, accentSoft, gold;
  final Color success, warning, danger;

  const AppSemanticColors({
    required this.bg,
    required this.surface,
    required this.surfaceSubtle,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.gold,
    required this.success,
    required this.warning,
    required this.danger,
  });

  @override
  AppSemanticColors copyWith() => this;

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) =>
      this;
}

extension AppThemeContext on BuildContext {
  AppSemanticColors get colors =>
      Theme.of(this).extension<AppSemanticColors>()!;
  TextTheme get textStyles => Theme.of(this).textTheme;
}

/// The app-wide push/pop transition (see [AppTheme.pageTransitionsTheme]
/// above): the incoming screen fades in while gliding up from the bottom.
///
/// A first version of this also faded the *outgoing* screen out via
/// `secondaryAnimation` (Material's "fade through" pattern), and used a
/// bare `Curves.easeOut` with no `reverseCurve`. Both made it read as
/// rushed rather than relaxed: `easeOut` decelerates so gently that most
/// of its motion is front-loaded into the first handful of frames, and
/// without a `reverseCurve` popping back re-used that same shape
/// backwards — i.e. sped away at the start of the pop instead of easing
/// out of it — so push and pop felt like two different animations. The
/// leaving screen's own fade-to-transparent, layered on top of the
/// incoming screen's fade-in, also meant two opacity changes competing
/// for attention in the same ~300ms window.
///
/// This version does one motion instead of two: only the incoming screen
/// animates (the outgoing one just sits there, covered), on
/// `easeOutCubic` — a curve with a true, gradual deceleration all the way
/// to the end rather than easeOut's abrupt tail-off — mirrored by
/// `easeInCubic` on the way back out for pop, and a slightly larger slide
/// distance so the glide actually reads instead of looking like a stutter.
class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
