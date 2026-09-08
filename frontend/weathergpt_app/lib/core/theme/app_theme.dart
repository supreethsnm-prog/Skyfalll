import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Builds the app's light and dark [ThemeData]. Tonal elevation
/// (Material 3's surface-tint model) is the primary elevation cue; real
/// drop shadows are reserved for genuinely floating surfaces (dialogs,
/// bottom sheets) rather than applied per-card — hence `cardTheme`
/// below sets elevation to 0 and relies on a surface-color shift alone.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: AppColors.cloudlight,
        surface: Colors.white,
        textPrimary: AppColors.lightTextPrimary,
        textSecondary: AppColors.lightTextSecondary,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: AppColors.monsoonInk,
        surface: AppColors.stormSlate,
        textPrimary: AppColors.darkTextPrimary,
        textSecondary: AppColors.darkTextSecondary,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    // fromSeed().copyWith(...) rather than ColorScheme(...) directly —
    // it fills in every Material 3 role Flutter's algorithm expects,
    // and copyWith only overrides the specific roles this palette cares
    // about, so this doesn't depend on knowing ColorScheme's full
    // constructor signature for the pinned Flutter version.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.marigold,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.marigold,
      onPrimary: AppColors.monsoonInk,
      secondary: AppColors.paddyGreen,
      onSecondary: Colors.white,
      error: AppColors.alertCrimson,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Inter',
      textTheme: TextTheme(
        displayLarge: AppTypography.display(textPrimary),
        headlineMedium: AppTypography.headline(textPrimary),
        titleMedium: AppTypography.title(textPrimary),
        bodyLarge: AppTypography.bodyLarge(textPrimary),
        bodyMedium: AppTypography.body(textPrimary),
        bodySmall: AppTypography.caption(textSecondary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.surface),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
    );
  }
}
