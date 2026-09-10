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

/// The REAL seeded ERA5 values, taken verbatim from the live endpoint,
/// including their full float precision — so the golden also proves the
/// screen rounds for display rather than printing 25.378503417968773.
///
/// Pune on 15 July in two consecutive years is the comparison this screen
/// exists for.
class _RealHistoricalApi implements HistoricalApi {
  @override
  Future<List<HistoricalCoverage>> fetchAvailable() async => const [
        HistoricalCoverage(
          locationName: 'Bhagalpur',
          latitude: 25.27,
          longitude: 87.23,
          dates: ['2024-07-15', '2024-01-15', '2023-07-15'],
        ),
        HistoricalCoverage(
          locationName: 'New Delhi',
          latitude: 28.61,
          longitude: 77.21,
          dates: ['2024-07-15', '2024-01-15', '2023-07-15'],
        ),
        HistoricalCoverage(
          locationName: 'Pune',
          latitude: 18.52,
          longitude: 73.86,
          dates: ['2024-07-15', '2024-01-15', '2023-07-15'],
        ),
      ];

  @override
  Future<HistoricalReading?> fetch(String location, String date) async {
    // Echoes the requested location so the fixture cannot contradict the
    // selector — the values below are Pune's real readings, used for any
    // location purely so the golden shows a genuine year-over-year pair.
    if (date == '2023-07-15') {
      return HistoricalReading(
        locationName: location,
        latitude: 18.52,
        longitude: 73.86,
        observationDate: '2023-07-15',
        temp2mC: 23.9114990234375,
        dewpoint2mC: 22.1039306640625,
        precipMm: 1.4305114746093750,
        windSpeed10mKmh: 14.204212951660156,
        windDirection10mDeg: 251.4013671875,
        mslpHpa: 1000.4127,
      );
    }
    return HistoricalReading(
      locationName: location,
      latitude: 18.52,
      longitude: 73.86,
      observationDate: '2024-07-15',
      temp2mC: 25.378503417968773,
      dewpoint2mC: 22.637597656250023,
      precipMm: 0.18262863159179688,
      windSpeed10mKmh: 8.732189204079713,
      windDirection10mDeg: 262.86885893510464,
      mslpHpa: 1001.87625,
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

  // Coverage loads, then a reading, then its comparison. Fixed pumps:
  // the loading spinner is indeterminate.
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
