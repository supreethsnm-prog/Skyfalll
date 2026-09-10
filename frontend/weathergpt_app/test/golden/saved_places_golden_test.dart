import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';
import 'package:weathergpt_app/features/saved/saved_places_screen.dart';

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

const _places = [
  GeocodeResult(
    displayName: 'Pune, Maharashtra',
    latitude: 18.5204,
    longitude: 73.8567,
    country: 'India',
    state: 'Maharashtra',
  ),
  GeocodeResult(
    displayName: 'Bhagalpur, Bihar',
    latitude: 25.27,
    longitude: 87.23,
    country: 'India',
    state: 'Bihar',
  ),
  GeocodeResult(
    displayName: 'New Delhi, Delhi',
    latitude: 28.6139,
    longitude: 77.2090,
    country: 'India',
    state: 'Delhi',
  ),
];

/// Distinct conditions per place, so the card gradients differ and the
/// "a stormy city looks stormy" intent is actually visible in the golden.
class _FakeWeatherApi implements WeatherApi {
  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    final code = switch (lat) {
      > 28 => 0, // Delhi: clear
      > 25 => 95, // Bhagalpur: thunderstorm
      _ => 63, // Pune: rain
    };
    return CurrentWeather(
      temperatureC: 24 + lat % 7,
      humidityPct: 78,
      weatherCode: code,
      windSpeedKmh: 18,
      windDirectionDeg: 247,
      observedAt: '2026-09-10T14:00',
      timezone: 'Asia/Kolkata',
    );
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon,
          {int days = 5}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Store implements SavedPlacesStore {
  _Store(this.places);
  final List<GeocodeResult> places;

  @override
  Future<List<GeocodeResult>> load() async => places;

  @override
  Future<void> save(List<GeocodeResult> next) async {}
}

Future<void> _pump(WidgetTester tester, List<GeocodeResult> places) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(400 * dpr, 700 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedPlacesStoreProvider.overrideWithValue(_Store(places)),
        weatherApiProvider.overrideWithValue(_FakeWeatherApi()),
      ],
      child: MaterialApp(
        // Pinned to mid-afternoon so the card skies are the day
        // gradients every run, not whatever hour the suite ran at.
        home: SavedPlacesScreen(now: DateTime(2026, 9, 10, 14)),
      ),
    ),
  );

  // Fixed pumps rather than pumpAndSettle: the loading spinner on each
  // card is indeterminate and would never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('saved places — populated', (tester) async {
    await _pump(tester, _places);

    await expectLater(
      find.byType(SavedPlacesScreen),
      matchesGoldenFile('goldens/saved_places.png'),
    );
  });

  testWidgets('saved places — empty', (tester) async {
    await _pump(tester, const []);

    await expectLater(
      find.byType(SavedPlacesScreen),
      matchesGoldenFile('goldens/saved_places_empty.png'),
    );
  });
}
