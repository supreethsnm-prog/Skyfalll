import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/core/theme/app_typography.dart';

void main() {
  group('AppTheme.dark', () {
    test('wires scaffoldBackgroundColor to AppColors.bgBase', () {
      expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.bgBase);
    });

    test('wires colorScheme.surface to AppColors.bgBase', () {
      expect(AppTheme.dark.colorScheme.surface, AppColors.bgBase);
    });

    test('uses AppTypography.sans as the theme fontFamily', () {
      // ThemeData no longer exposes a top-level `fontFamily` getter (only
      // a constructor param that seeds the default text theme); the
      // actually-rendered face is whatever the resolved textTheme carries,
      // so check that directly across every style AppTheme.dark sets.
      final textTheme = AppTheme.dark.textTheme;
      final styles = [
        textTheme.displayLarge,
        textTheme.headlineLarge,
        textTheme.titleLarge,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.labelLarge,
        textTheme.bodySmall,
      ];
      for (final style in styles) {
        expect(style?.fontFamily, AppTypography.sans, reason: '$style');
      }
    });

    test('appBarTheme floats transparently over content: transparent fill, '
        'zero elevation', () {
      final appBarTheme = AppTheme.dark.appBarTheme;
      expect(appBarTheme.backgroundColor, Colors.transparent,
          reason: 'an opaque toolbar would undo the floating-chrome look');
      expect(appBarTheme.elevation, 0);
      expect(appBarTheme.scrolledUnderElevation, 0,
          reason: 'scrolling must not raise a shadow/tint under the AppBar');
    });

    test('is a dark Material 3 theme', () {
      expect(AppTheme.dark.useMaterial3, isTrue);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });
  });
}
