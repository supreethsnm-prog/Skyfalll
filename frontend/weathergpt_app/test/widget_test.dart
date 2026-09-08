import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/core/theme/theme_mode_provider.dart';
import 'package:weathergpt_app/features/gallery/gallery_screen.dart';
import 'package:weathergpt_app/main.dart';

void main() {
  testWidgets('WeatherGptApp boots to the Home tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeatherGptApp()));
    await tester.pumpAndSettle();

    expect(find.text('Home — coming soon'), findsOneWidget);
  });

  testWidgets(
    'toggling the gallery theme button flips the rendered brightness',
    (tester) async {
      // GalleryScreen contains a LoadingView with an indeterminate
      // CircularProgressIndicator, which animates forever — pumpAndSettle
      // would hang waiting for it to stop. A plain pump() plus one fixed
      // Duration advance is enough to let the first frame build without
      // depending on the animation ever settling.
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              final themeMode = ref.watch(themeModeProvider);
              return MaterialApp(
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                home: const GalleryScreen(),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final scaffoldFinder = find.byType(Scaffold).first;
      final initialBrightness =
          Theme.of(tester.element(scaffoldFinder)).brightness;

      // The provider starts at ThemeMode.system, which resolves to light
      // brightness in the test environment's default platformDispatcher
      // — assert that starting point explicitly so a no-op toggle
      // (e.g. a button wired to nothing) can't accidentally pass below.
      expect(initialBrightness, Brightness.light);

      await tester.tap(find.byTooltip('Toggle light/dark theme'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final toggledBrightness =
          Theme.of(tester.element(scaffoldFinder)).brightness;

      expect(toggledBrightness, Brightness.dark);
      expect(toggledBrightness, isNot(initialBrightness));
    },
  );
}
