import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// [TextTheme] built entirely from Space Mono.
///
/// Space Mono ships only Regular (400) and Bold (700) — no italic or medium
/// weights. Every style maps to one of these two, which reinforces the
/// terminal / Swiss-grid poster aesthetic.
abstract final class AppTextStyles {
  static TextTheme get textTheme => TextTheme(
        // Large display — rep counter big number
        displayLarge: GoogleFonts.spaceMono(
          fontSize: 57,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          color: AppColors.textPrimary,
        ),
        // Countdown overlay number
        displayMedium: GoogleFonts.spaceMono(
          fontSize: 45,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        displaySmall: GoogleFonts.spaceMono(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        // Screen titles
        headlineLarge: GoogleFonts.spaceMono(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.spaceMono(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineSmall: GoogleFonts.spaceMono(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        // Card headings / section titles
        titleLarge: GoogleFonts.spaceMono(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.spaceMono(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          color: AppColors.textPrimary,
        ),
        titleSmall: GoogleFonts.spaceMono(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: AppColors.textPrimary,
        ),
        // Body text
        bodyLarge: GoogleFonts.spaceMono(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.spaceMono(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          color: AppColors.textPrimary,
        ),
        bodySmall: GoogleFonts.spaceMono(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
          color: AppColors.textSecondary,
        ),
        // Buttons and captions
        labelLarge: GoogleFonts.spaceMono(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: AppColors.textPrimary,
        ),
        // Debug badge, captions
        labelMedium: GoogleFonts.spaceMono(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
          color: AppColors.textSecondary,
        ),
        labelSmall: GoogleFonts.spaceMono(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
          color: AppColors.textSecondary,
        ),
      );
}
