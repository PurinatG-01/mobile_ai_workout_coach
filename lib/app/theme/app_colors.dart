import 'package:flutter/material.dart';

/// Central color palette — monochrome only.
///
/// Light background, black type. No accent colors.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Base — monochrome scale (light → dark)
  // ---------------------------------------------------------------------------

  /// True white. Main scaffold background.
  static const Color bgPrimary = Color(0xFFFFFFFF);

  /// Off-white surface. Cards, input areas.
  static const Color bgSurface = Color(0xFFF5F5F5);

  /// Light grey elevated surface. Overlays, badges.
  static const Color bgElevated = Color(0xFFEEEEEE);

  /// Subtle border/divider. Low-contrast rule lines.
  static const Color borderSubtle = Color(0xFFD6D6D6);

  /// Strong border. Visible separators, card outlines.
  static const Color borderStrong = Color(0xFF999999);

  /// Primary text. Headings, values, main labels.
  static const Color textPrimary = Color(0xFF0A0A0A);

  /// Secondary text. Captions, muted labels.
  static const Color textSecondary = Color(0xFF555555);

  /// Disabled / placeholder text.
  static const Color textDisabled = Color(0xFFAAAAAA);

  // ---------------------------------------------------------------------------
  // Convenience — opacity variants for overlays on camera feed
  // ---------------------------------------------------------------------------

  static const Color bgOverlay55 = Color(0x8CFFFFFF);
  static const Color bgOverlay80 = Color(0xCCFFFFFF);
}
