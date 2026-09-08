import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/features/gallery/gallery_screen.dart';

/// Registers a real bundled font under `family` so golden renders use the
/// actual Sora/Inter/IBMPlexMono glyphs rather than the test environment's
/// placeholder font. `flutter test` runs with the package root as the
/// working directory, so `assetPath` is relative to
/// `frontend/weathergpt_app/`, matching the `assets:` paths in pubspec.yaml.
/// These three are required app assets — a missing file here is a real
/// setup problem, so this throws (via `readAsBytes`) rather than swallowing
/// it.
Future<void> _loadFont(String family, String assetPath) async {
  final file = File(assetPath);
  final Uint8List bytes = await file.readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

/// Best-effort registration of the "MaterialIcons" font so `Icon(...)`
/// widgets (weather icons, the theme-toggle icon, error/empty-state icons)
/// render as real glyphs instead of tofu boxes in the golden. Unlike the
/// three app fonts above, this file lives inside the Flutter SDK install,
/// not this repo, so its location is derived from the `FLUTTER_ROOT`
/// environment variable (set by `frontend/dev-env.ps1`, and by `flutter
/// test` itself) rather than hardcoded — and if it can't be found, the
/// gallery still renders correctly, just with icon glyphs missing, so this
/// is allowed to fail silently rather than break the whole suite over a
/// cosmetic detail outside the app's own asset set.
Future<void> _loadMaterialIconsFontBestEffort() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;

  final file = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (!file.existsSync()) return;

  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

/// Pumps [GalleryScreen] under the given [theme] at a phone-shaped surface.
///
/// Deliberately avoids `pumpAndSettle()`: the gallery's `LoadingView`
/// contains an indeterminate `CircularProgressIndicator`, whose animation
/// never stops, so `pumpAndSettle` would either time out or (if it didn't)
/// leave the spinner at a run-dependent angle. Instead this pumps once to
/// build, then advances the test's virtual clock by one fixed duration —
/// since flutter_test's clock starts at zero and advances deterministically
/// (not by wall time), the spinner lands on the exact same frame every run.
Future<void> _pumpGallery(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(1080, 2430);
  tester.view.devicePixelRatio = 2.7;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: const GalleryScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Sora', 'assets/fonts/Sora-Variable.ttf');
    await _loadFont('Inter', 'assets/fonts/Inter-Variable.ttf');
    await _loadFont('IBMPlexMono', 'assets/fonts/IBMPlexMono-Regular.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('component gallery — light theme', (tester) async {
    await _pumpGallery(tester, AppTheme.light);

    await expectLater(
      find.byType(GalleryScreen),
      matchesGoldenFile('goldens/gallery_light.png'),
    );
  });

  testWidgets('component gallery — dark theme', (tester) async {
    await _pumpGallery(tester, AppTheme.dark);

    await expectLater(
      find.byType(GalleryScreen),
      matchesGoldenFile('goldens/gallery_dark.png'),
    );
  });
}
