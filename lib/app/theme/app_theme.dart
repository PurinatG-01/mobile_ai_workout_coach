import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Assembles the app's [ThemeData].
///
/// Light-only. White background, black type — Swiss grid / terminal-poster
/// aesthetic with Space Mono.
abstract final class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.textPrimary,
      onPrimary: AppColors.bgPrimary,
      primaryContainer: AppColors.bgElevated,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.textSecondary,
      onSecondary: AppColors.bgPrimary,
      secondaryContainer: AppColors.bgSurface,
      onSecondaryContainer: AppColors.textSecondary,
      tertiary: AppColors.textSecondary,
      onTertiary: AppColors.bgPrimary,
      tertiaryContainer: AppColors.bgSurface,
      onTertiaryContainer: AppColors.textSecondary,
      error: AppColors.textPrimary,
      onError: AppColors.bgPrimary,
      errorContainer: AppColors.bgElevated,
      onErrorContainer: AppColors.textPrimary,
      surface: AppColors.bgSurface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.bgElevated,
      surfaceContainerHigh: AppColors.bgElevated,
      surfaceContainer: AppColors.bgSurface,
      surfaceContainerLow: AppColors.bgPrimary,
      surfaceContainerLowest: AppColors.bgPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.borderSubtle,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.bgPrimary,
      inversePrimary: AppColors.bgSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bgPrimary,
      textTheme: AppTextStyles.textTheme,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.bgPrimary,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),

      // FilledButton — black fill, white label
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.bgPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          textStyle: AppTextStyles.textTheme.labelLarge,
        ),
      ),

      // OutlinedButton — white fill, black border
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.textPrimary),
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          textStyle: AppTextStyles.textTheme.labelLarge,
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: AppTextStyles.textTheme.labelLarge,
        ),
      ),

      // Card — white with black hairline border, sharp corners
      cardTheme: const CardThemeData(
        color: AppColors.bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.borderSubtle),
        ),
        margin: EdgeInsets.zero,
      ),

      // Divider — hairline rule
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: AppTextStyles.textTheme.bodyMedium?.copyWith(
          color: AppColors.bgPrimary,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Icon
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 24,
      ),
    );
  }
}
