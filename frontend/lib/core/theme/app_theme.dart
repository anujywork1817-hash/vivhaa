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
          minimumSize: const Size.fromHeight(52),
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
          minimumSize: const Size.fromHeight(52),
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
      dividerTheme: DividerThemeData(color: line, thickness: 1),
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
