import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/home/home_screen.dart';

/// Registers a real bundled font so goldens use actual Roboto glyphs
/// rather than the test environment's placeholder. `flutter test` runs
/// with the package root as the working directory, so the path matches
/// pubspec.yaml's `assets:` entries. A missing file here is a real setup
/// problem, so this throws rather than swallowing it.
Future<void> _loadFont(String family, String assetPath) async {
  final bytes = await File(assetPath).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

/// Best-effort MaterialIcons registration so `Icon(...)` renders glyphs
/// instead of tofu. Lives in the Flutter SDK, not this repo, so it is
/// located via FLUTTER_ROOT and allowed to fail silently — a missing icon
/// font is cosmetic and outside the app's own asset set.
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

// Plausible Pune monsoon values — the goldens get shown to people, so
// the data should read as real weather rather than lorem numbers.
CurrentWeather _weather({int code = 63}) => CurrentWeather(
      temperatureC: 24.4,
      humidityPct: 78,
      weatherCode: code,
      windSpeedKmh: 18.2,
      windDirectionDeg: 247,
      observedAt: '2026-09-09T14:00',
      timezone: 'Asia/Kolkata',
    );

final _forecast = <ForecastDay>[
  const ForecastDay(
      forecastDate: '2026-09-09',
      weatherCode: 63,
      tempMaxC: 28.4,
      tempMinC: 23.1),
  const ForecastDay(
      forecastDate: '2026-09-10',
      weatherCode: 80,
      tempMaxC: 29.0,
      tempMinC: 23.6),
  const ForecastDay(
      forecastDate: '2026-09-11',
      weatherCode: 95,
      tempMaxC: 27.2,
      tempMinC: 22.8),
  const ForecastDay(
      forecastDate: '2026-09-12',
      weatherCode: 3,
      tempMaxC: 30.1,
      tempMinC: 24.0),
  const ForecastDay(
      forecastDate: '2026-09-13',
      weatherCode: 1,
      tempMaxC: 31.5,
      tempMinC: 24.4),
];

class _FakeWeatherApi implements WeatherApi {
  _FakeWeatherApi({this.code = 63, this.fail = false});

  final int code;
  final bool fail;

  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    if (fail) throw const NetworkConnectionError();
    return _weather(code: code);
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon,
      {int days = 5}) async {
    if (fail) throw const NetworkConnectionError();
    return _forecast;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeAlertsApi implements AlertsApi {
  _FakeAlertsApi({this.alerts = const []});

  final List<AlertSummary> alerts;

  @override
  Future<List<AlertSummary>> fetchAlerts() async => alerts;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required DateTime now,
  int code = 63,
  List<AlertSummary> alerts = const [],
  bool fail = false,
}) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(400 * dpr, 880 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherApiProvider
            .overrideWithValue(_FakeWeatherApi(code: code, fail: fail)),
        alertsApiProvider.overrideWithValue(_FakeAlertsApi(alerts: alerts)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: HomeScreen(now: now),
      ),
    ),
  );

  // No pumpAndSettle: the loading state holds an indeterminate
  // CircularProgressIndicator whose animation never stops, so
  // pumpAndSettle would never return. Fixed pumps against the test's
  // virtual clock are deterministic instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('home — day sky, moderate rain', (tester) async {
    await _pumpHome(tester, now: DateTime(2026, 9, 9, 14));

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_day.png'),
    );
  });

  testWidgets('home — day sky, clear', (tester) async {
    // The clear-day sky is the one untouched by the contrast darkening,
    // so it shows the gradient system at full strength.
    await _pumpHome(tester, now: DateTime(2026, 9, 9, 11), code: 0);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_clear.png'),
    );
  });

  testWidgets('home — night sky, clear', (tester) async {
    await _pumpHome(tester, now: DateTime(2026, 9, 9, 22), code: 0);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_night.png'),
    );
  });

  testWidgets('home — severe alert in force', (tester) async {
    await _pumpHome(
      tester,
      now: DateTime(2026, 9, 9, 18),
      code: 95,
      alerts: const [
        AlertSummary(
          id: 1,
          severity: 'Severe',
          eventType: 'Heavy Rainfall Warning',
          areaDescription: 'Delhi NCR and surrounding districts',
          // Must be within HomeController's 100km radius of the default
          // location (New Delhi) or the controller correctly filters it
          // out and this golden silently loses its subject.
          latitude: 28.61,
          longitude: 77.21,
        ),
      ],
    );

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_alert.png'),
    );
  });

  testWidgets('home — error state', (tester) async {
    // Error states are where polish usually dies, and this project has
    // already shipped one illegible error screen that only eye-inspection
    // of a golden caught.
    await _pumpHome(tester, now: DateTime(2026, 9, 9, 14), fail: true);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_error.png'),
    );
  });
}
