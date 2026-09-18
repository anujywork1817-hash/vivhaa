import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Roboto throughout — the same base font WhatsApp and Instagram use —
/// instead of a display serif (Fraunces) for headings mixed with a
/// separate body face (Inter), for one consistent look everywhere.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
        displaySmall: GoogleFonts.roboto(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: ink,
          height: 1.15,
        ),
        headlineMedium: GoogleFonts.roboto(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: ink,
          height: 1.2,
        ),
        headlineSmall: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleMedium: GoogleFonts.roboto(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleSmall: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: GoogleFonts.roboto(fontSize: 15.5, color: ink, height: 1.45),
        bodyMedium: GoogleFonts.roboto(fontSize: 14, color: ink, height: 1.4),
        bodySmall: GoogleFonts.roboto(fontSize: 12.5, color: muted, height: 1.35),
        labelLarge: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onAccent,
          letterSpacing: 0.2,
        ),
        labelSmall: GoogleFonts.roboto(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted,
          letterSpacing: 0.6,
        ),
      );
}
