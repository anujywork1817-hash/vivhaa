import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Display face (Fraunces) carries the "invitation" personality in
/// headings; Inter handles everything read at length or in dense UI.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
        displaySmall: GoogleFonts.fraunces(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: ink,
          height: 1.15,
        ),
        headlineMedium: GoogleFonts.fraunces(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: ink,
          height: 1.2,
        ),
        headlineSmall: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: GoogleFonts.inter(fontSize: 15.5, color: ink, height: 1.45),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: ink, height: 1.4),
        bodySmall: GoogleFonts.inter(fontSize: 12.5, color: muted, height: 1.35),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onAccent,
          letterSpacing: 0.2,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted,
          letterSpacing: 0.6,
        ),
      );
}
