import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/data/historical_api.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/historical/historical_controller.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';
import 'package:weathergpt_app/features/historical/historical_screen.dart';

import '../support/fake_apis.dart';

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

/// A real Open-Meteo Archive shape (Pune, two consecutive 15 Julys) — the
/// comparison this screen exists for.
class _RealHistoricalApi implements HistoricalApi {
  @override
  Future<HistoricalArchive?> fetchArchive({
    required double latitude,
    required double longitude,
    required String date,
    String? name,
  }) async {
    return const HistoricalArchive(
      latitude: 18.52,
      longitude: 73.86,
      locationName: 'Pune, Maharashtra',
      reading: ArchiveReading(
        date: '2024-07-15',
        tempMaxC: 29.7,
        tempMinC: 22.3,
        tempMeanC: 25.4,
        precipSumMm: 18.3,
        windSpeedMaxKmh: 22.6,
        windDirectionDominantDeg: 262.9,
      ),
      previousYearReading: ArchiveReading(
        date: '2023-07-15',
        tempMaxC: 28.1,
        tempMinC: 20.9,
        tempMeanC: 23.9,
        precipSumMm: 6.4,
        windSpeedMaxKmh: 18.9,
        windDirectionDominantDeg: 251.4,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester tester) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(400 * dpr, 1000 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      // Listed explicitly rather than spreading fakeApiOverrides: that
      // list already stubs the historical API, and this golden needs its
      // own real-valued fixture. Riverpod rejects overriding the same
      // provider twice in one container.
      overrides: [
        weatherApiProvider.overrideWithValue(FakeWeatherApi()),
        alertsApiProvider.overrideWithValue(FakeAlertsApi()),
        airQualityApiProvider.overrideWithValue(FakeAirQualityApi()),
        deviceLocationProvider.overrideWithValue(const FakeDeviceLocation()),
        geocodingApiProvider.overrideWithValue(const FakeGeocodingApi()),
        alertsSocketProvider.overrideWithValue(FakeAlertsSocket()),
        savedPlacesStoreProvider.overrideWithValue(FakeSavedPlacesStore()),
        conversationStoreProvider.overrideWithValue(FakeConversationStore()),
        historicalApiProvider.overrideWithValue(_RealHistoricalApi()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const HistoricalScreen(),
      ),
    ),
  );

  // Home resolves, then the archive reading loads. Fixed pumps: the
  // loading spinner is indeterminate.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('historical — reading with year-over-year comparison',
      (tester) async {
    await _pump(tester);

    await expectLater(
      find.byType(HistoricalScreen),
      matchesGoldenFile('goldens/historical.png'),
    );
  });
}
