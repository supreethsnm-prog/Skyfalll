import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/core/voice_language_prefs.dart';
import 'package:weathergpt_app/data/air_quality_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/alerts_socket.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/nwp_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/home/home_screen.dart';
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
      uvIndex: 6.1,
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
  _FakeWeatherApi({this.code = 63});
  final int code;

  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async => _weather(code: code);

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon, {int days = 5}) async => _forecast;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAirQualityApi implements AirQualityApi {
  @override
  Future<AirQuality> fetchCurrent(double lat, double lon) async => const AirQuality(
        observedAt: '2026-09-09T14:00',
        usAqi: 156,
        pm25: 64.8,
        pm10: 118.2,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNwpApi implements NwpApi {
  @override
  Future<List<NwpPoint>> fetchForecast(double lat, double lon) async => const [];
}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptySavedStore implements SavedPlacesStore {
  @override
  Future<List<GeocodeResult>> load() async => const [];

  @override
  Future<void> save(List<GeocodeResult> places) async {}
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
  @override
  Future<List<AlertSummary>> fetchAlerts() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpHomeHindi(
  WidgetTester tester, {
  required DateTime now,
  int code = 63,
  double height = 880,
}) async {
  const dpr = 2.0;
  tester.view.physicalSize = Size(400 * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceLanguagePrefsProvider
            .overrideWithValue(FakeVoiceLanguagePrefs('hi')),
        weatherApiProvider.overrideWithValue(_FakeWeatherApi(code: code)),
        alertsApiProvider.overrideWithValue(_FakeAlertsApi()),
        airQualityApiProvider.overrideWithValue(_FakeAirQualityApi()),
        nwpApiProvider.overrideWithValue(_FakeNwpApi()),
        deviceLocationProvider.overrideWithValue(_FixedLocation()),
        geocodingApiProvider.overrideWithValue(_FixedGeocoding()),
        alertsSocketProvider.overrideWithValue(_SilentSocket()),
        savedPlacesStoreProvider.overrideWithValue(_EmptySavedStore()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: HomeScreen(now: now),
      ),
    ),
  );

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

  testWidgets('home — hindi locale', (tester) async {
    await _pumpHomeHindi(tester, now: DateTime(2026, 9, 9, 14));

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_hindi.png'),
    );
  });
}
