import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/data/marine_api.dart';
import 'package:weathergpt_app/features/marine/marine_controller.dart';
import 'package:weathergpt_app/features/marine/marine_screen.dart';

Future<void> _loadFont(String family, String assetPath) async {
  final bytes = await File(assetPath).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

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

/// Transparent tiles. flutter_map's default provider caches through
/// path_provider, which throws MissingPluginException in a widget test —
/// and OSM must never be hit from a test regardless.
class _TransparentTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(TileProvider.transparentImage);
}

/// Serves REAL INCOIS geometry, sampled from the live endpoint and stored
/// verbatim in `pfz_fixture.json` (8 zones off the Maharashtra-Goa coast,
/// thinned to every 30th point so the fixture stays readable).
///
/// Using real coordinates rather than invented ones is the point: if the
/// lon/lat order were ever swapped, these zones would leave the Arabian
/// Sea and land somewhere impossible, and this golden would show it.
class _FixtureMarineApi implements MarineApi {
  @override
  Future<List<PfzZone>> fetchPfzZones() async {
    final raw = File('test/golden/pfz_fixture.json').readAsStringSync();
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => PfzZone.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester tester) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(400 * dpr, 800 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marineApiProvider.overrideWithValue(_FixtureMarineApi()),
        marineTileProviderProvider
            .overrideWithValue(_TransparentTileProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const MarineScreen(),
      ),
    ),
  );

  // Fixed pumps: the loading spinner is indeterminate, and map tiles
  // never resolve in a test (no network), which is fine — the zone
  // polylines are what this golden is for.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('marine — zones drawn over the map', (tester) async {
    await _pump(tester);

    await expectLater(
      find.byType(MarineScreen),
      matchesGoldenFile('goldens/marine.png'),
    );
  });
}
