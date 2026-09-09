import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/features/gallery/gallery_screen.dart';

/// Registers a real bundled font under [family] so golden renders use the
/// actual Roboto glyphs rather than the test environment's placeholder
/// font. `flutter test` runs with the package root as the working
/// directory, so [assetPath] is relative to `frontend/weathergpt_app/`,
/// matching the `assets:` paths in pubspec.yaml. Both are required app
/// assets — a missing file here is a real setup problem, so this throws
/// (via `readAsBytes`) rather than swallowing it.
Future<void> _loadFont(String family, String assetPath) async {
  final file = File(assetPath);
  final Uint8List bytes = await file.readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

/// Best-effort registration of the "MaterialIcons" font so `Icon(...)`
/// widgets render as real glyphs instead of tofu boxes. Unlike the app
/// fonts above, this file lives inside the Flutter SDK install rather
/// than this repo, so its location comes from `FLUTTER_ROOT` (set by
/// `frontend/dev-env.ps1`, and by `flutter test` itself). If it cannot be
/// found the gallery still renders correctly, just without icon glyphs,
/// so this fails silently rather than breaking the suite over a cosmetic
/// detail outside the app's own asset set.
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

/// Pumps one gallery [section] at a phone-width surface tall enough to
/// hold it without scrolling, so the golden captures the whole section
/// rather than a clipped viewport.
///
/// Deliberately avoids `pumpAndSettle()` — this project has twice hit the
/// bug where it never returns on a repeating animation. The menu route's
/// fade is finite, so advancing the virtual clock by a fixed duration
/// settles it deterministically: flutter_test's clock starts at zero and
/// advances by exactly what it is told, never by wall time.
Future<void> _pumpSection(
  WidgetTester tester,
  GallerySection section, {
  required double logicalHeight,
}) async {
  const dpr = 2.0;
  const logicalWidth = 400.0;

  tester.view.physicalSize = Size(logicalWidth * dpr, logicalHeight * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: GalleryScreen(section: section),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('gallery — type scale', (tester) async {
    await _pumpSection(tester, GallerySection.type, logicalHeight: 620);

    await expectLater(
      find.byType(GalleryScreen),
      matchesGoldenFile('goldens/gallery_type.png'),
    );
  });

  testWidgets('gallery — chrome and chat', (tester) async {
    // Chrome and chat are pumped together: they are the two halves of the
    // chat surface and are judged against each other (the boxed user turn
    // beside the unboxed assistant turn, both under the same round
    // buttons), so one PNG showing them together is the useful artefact.
    await _pumpSection(tester, GallerySection.chrome, logicalHeight: 200);
    await expectLater(
      find.byType(GalleryScreen),
      matchesGoldenFile('goldens/gallery_chrome.png'),
    );

    await _pumpSection(tester, GallerySection.chat, logicalHeight: 520);
    await expectLater(
      find.byType(GalleryScreen),
      matchesGoldenFile('goldens/gallery_chat.png'),
    );
  });

  testWidgets('gallery — overflow menu open', (tester) async {
    await _pumpSection(tester, GallerySection.menus, logicalHeight: 420);

    await tester.tap(find.byKey(const Key('gallery-overflow-launcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Captured at the app root, not the screen: the menu is a PopupRoute
    // living in the Navigator's overlay, so a GalleryScreen-scoped capture
    // would miss the very thing under review. This also exercises the
    // default launcher-anchored positioning path, which has no unit test.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gallery_menu_overflow.png'),
    );
  });

  testWidgets('gallery — attach menu open', (tester) async {
    await _pumpSection(tester, GallerySection.menus, logicalHeight: 420);

    await tester.tap(find.byKey(const Key('gallery-attach-launcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gallery_menu_attach.png'),
    );
  });

  testWidgets('gallery — sky gradients and glass panels', (tester) async {
    await _pumpSection(tester, GallerySection.sky, logicalHeight: 1120);

    await expectLater(
      find.byType(GalleryScreen),
      matchesGoldenFile('goldens/gallery_sky.png'),
    );
  });
}
