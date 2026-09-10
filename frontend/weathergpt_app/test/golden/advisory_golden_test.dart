import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/data/advisory_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/advisory/advisory_controller.dart';
import 'package:weathergpt_app/features/advisory/advisory_screen.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';

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

const _forecastBasis = [
  ForecastDay(
    forecastDate: '2026-09-10',
    weatherCode: 63,
    tempMaxC: 33.7,
    tempMinC: 26.4,
  ),
  ForecastDay(
    forecastDate: '2026-09-11',
    weatherCode: 96,
    tempMaxC: 32.2,
    tempMinC: 26.0,
  ),
];

/// Deliberately mixed bands, including the backend's UNKNOWN, so the
/// golden shows all four severity colours AND the neutral treatment an
/// unknown risk must get.
class _FakeAdvisoryApi implements AdvisoryApi {
  @override
  Future<UrbanAdvisory> fetchUrban(double lat, double lon, {int days = 5}) async {
    return const UrbanAdvisory(
      latitude: 28.61,
      longitude: 77.21,
      generatedAt: '2026-09-10T08:18:03+05:30',
      riskSummary: UrbanRiskSummary(
        waterloggingRisk: 'HIGH',
        heatRisk: 'MODERATE',
        windRisk: 'UNKNOWN',
      ),
      advisories: [
        'Heavy rain forecast (>=64.5mm/day) — expect waterlogging on '
            'low-lying roads and underpasses; avoid non-essential travel.',
        'Thunderstorm warning in force — secure loose hoardings and avoid '
            'sheltering under trees.',
      ],
      activeAlerts: [
        AlertSummary(
          id: 1,
          severity: 'Orange',
          eventType: 'Heavy Rainfall Warning',
          areaDescription: 'Delhi NCR and surrounding districts',
          latitude: 28.61,
          longitude: 77.21,
        ),
      ],
      forecastBasis: _forecastBasis,
    );
  }

  @override
  Future<AgricultureAdvisory> fetchAgriculture(
    double lat,
    double lon, {
    String? crop,
    int days = 5,
  }) async {
    return const AgricultureAdvisory(
      latitude: 28.61,
      longitude: 77.21,
      crop: null,
      generatedAt: '2026-09-10T08:18:02+05:30',
      advisories: [
        'Very heavy rain forecast (>=115.6mm/day) — hold off sowing, '
            'fertilizer, and pesticide application; ensure field drainage '
            'is clear.',
        'No significant rain expected after Friday — plan irrigation '
            'accordingly.',
      ],
      activeAlerts: [],
      forecastBasis: _forecastBasis,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester tester) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(400 * dpr, 1150 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      // Listed explicitly rather than spreading fakeApiOverrides: that
      // list already stubs the advisory API, and this golden needs its
      // own richer fixture (mixed bands including UNKNOWN). Riverpod
      // rejects overriding the same provider twice in one container.
      overrides: [
        weatherApiProvider.overrideWithValue(FakeWeatherApi()),
        alertsApiProvider.overrideWithValue(FakeAlertsApi()),
        airQualityApiProvider.overrideWithValue(FakeAirQualityApi()),
        deviceLocationProvider.overrideWithValue(const FakeDeviceLocation()),
        geocodingApiProvider.overrideWithValue(const FakeGeocodingApi()),
        alertsSocketProvider.overrideWithValue(FakeAlertsSocket()),
        savedPlacesStoreProvider.overrideWithValue(FakeSavedPlacesStore()),
        conversationStoreProvider.overrideWithValue(FakeConversationStore()),
        advisoryApiProvider.overrideWithValue(_FakeAdvisoryApi()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const AdvisoryScreen(),
      ),
    ),
  );

  // Home resolves its location first, then advisories load off it. Fixed
  // pumps rather than pumpAndSettle: the loading spinner is indeterminate.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('advisories — populated', (tester) async {
    await _pump(tester);

    await expectLater(
      find.byType(AdvisoryScreen),
      matchesGoldenFile('goldens/advisories.png'),
    );
  });
}
