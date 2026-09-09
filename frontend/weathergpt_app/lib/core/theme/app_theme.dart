import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Dark-only for this build. Light mode is deliberately deferred, but
/// every token is resolved through this theme rather than hardcoded in
/// widgets, so adding a light palette later is additive.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.textPrimary,
      surface: AppColors.bgBase,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceRaised,
      outline: AppColors.divider,
      error: AppColors.destructive,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bgBase,
      canvasColor: AppColors.bgBase,
      fontFamily: AppTypography.sans,
      textTheme: TextTheme(
        displayLarge: AppTypography.hero(AppColors.textPrimary),
        headlineLarge: AppTypography.wordmark(AppColors.textPrimary),
        titleLarge: AppTypography.title(AppColors.textPrimary),
        bodyLarge: AppTypography.body(AppColors.textPrimary),
        bodyMedium: AppTypography.body(AppColors.textPrimary),
        labelLarge: AppTypography.label(AppColors.textSecondary),
        bodySmall: AppTypography.caption(AppColors.textSecondary),
      ),
      dividerColor: AppColors.divider,
      // Chrome floats directly on the background — no toolbar surface.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.menu),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
