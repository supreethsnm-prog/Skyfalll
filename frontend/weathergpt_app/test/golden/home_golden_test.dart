import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/data/air_quality_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/alerts_socket.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
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
      apparentTemperatureC: 27.6,
      pressureHpa: 1004.2,
      dewPointC: 21.3,
      visibilityKm: 6.4,
      hourly: const [
        HourlyPoint(time: '2026-09-09T14:00', temperatureC: 24.4, weatherCode: 3),
        HourlyPoint(time: '2026-09-09T15:00', temperatureC: 25.1, weatherCode: 3),
        HourlyPoint(time: '2026-09-09T16:00', temperatureC: 25.4, weatherCode: 80),
        HourlyPoint(time: '2026-09-09T17:00', temperatureC: 24.8, weatherCode: 61),
        HourlyPoint(time: '2026-09-09T18:00', temperatureC: 23.9, weatherCode: 63),
        HourlyPoint(time: '2026-09-09T19:00', temperatureC: 23.2, weatherCode: 63),
        HourlyPoint(time: '2026-09-09T20:00', temperatureC: 22.8, weatherCode: 61),
        HourlyPoint(time: '2026-09-09T21:00', temperatureC: 22.4, weatherCode: 80),
      ],
    );

final _forecast = <ForecastDay>[
  const ForecastDay(
    forecastDate: '2026-09-09',
    weatherCode: 63,
    tempMaxC: 28.4,
    tempMinC: 23.1,
    uvIndexMax: 7.35,
    sunrise: '2026-09-09T06:12',
    sunset: '2026-09-09T18:42',
  ),
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

class _FakeAirQualityApi implements AirQualityApi {
  _FakeAirQualityApi({this.fail = false});

  final bool fail;

  @override
  Future<AirQuality> fetchCurrent(double lat, double lon) async {
    if (fail) throw const NetworkConnectionError();
    return const AirQuality(
      observedAt: '2026-09-09T14:00',
      usAqi: 156,
      pm25: 64.8,
      pm10: 118.2,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Pins the hero's place name so goldens never depend on a live
/// reverse-geocode call.
class _FixedGeocoding implements GeocodingApi {
  @override
  Future<GeocodeResult?> reverse(double lat, double lon) async =>
      const GeocodeResult(
        displayName: 'New Delhi, India',
        latitude: 28.6139,
        longitude: 77.2090,
        country: 'India',
        state: 'Delhi',
      );

  @override
  Future<GeocodeResult?> search(String query) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _SilentSocket implements AlertsSocket {
  @override
  Stream<List<AlertSummary>> get newAlerts => const Stream.empty();

  @override
  void dispose() {}
}

class _FixedLocation implements DeviceLocation {
  @override
  Future<LocationResult> current() async =>
      const LocationFixed(28.6139, 77.2090);
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
  // Home scrolls past a phone viewport. A taller surface renders the whole
  // page into one image for design review and for the pitch deck; the
  // default height is a real phone, showing what actually fits on screen.
  double height = 880,
}) async {
  const dpr = 2.0;
  tester.view.physicalSize = Size(400 * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherApiProvider
            .overrideWithValue(_FakeWeatherApi(code: code, fail: fail)),
        alertsApiProvider.overrideWithValue(_FakeAlertsApi(alerts: alerts)),
        airQualityApiProvider
            .overrideWithValue(_FakeAirQualityApi(fail: fail)),
        // Pinned so goldens never depend on a real device fix, and so the
        // hero always renders the same place name.
        deviceLocationProvider.overrideWithValue(_FixedLocation()),
        geocodingApiProvider.overrideWithValue(_FixedGeocoding()),
        alertsSocketProvider.overrideWithValue(_SilentSocket()),
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

  testWidgets('home — full page, every tile', (tester) async {
    await _pumpHome(
      tester,
      now: DateTime(2026, 9, 9, 11),
      code: 0,
      height: 1500,
    );

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_full.png'),
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
