import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/historical_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/historical/historical_controller.dart';
import 'package:weathergpt_app/features/historical/historical_screen.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

import '../../support/fake_apis.dart';

/// Historical prefers Home's current location as its default, so these
/// tests fix Home's state directly, mirroring `aviation_screen_test.dart`.
class _FixedHomeController extends HomeController {
  _FixedHomeController(this._initial);
  final HomeUiState _initial;

  @override
  HomeUiState build() => _initial;
}

const _weather = CurrentWeather(
  temperatureC: 28.0,
  humidityPct: 70,
  weatherCode: 61,
  windSpeedKmh: 14,
  windDirectionDeg: 200,
  observedAt: '2026-09-10T08:00:00+05:30',
  timezone: 'Asia/Kolkata',
);

const _puneHome = GeocodeResult(
  displayName: 'Pune, Maharashtra',
  latitude: 18.5204,
  longitude: 73.8567,
  country: 'India',
  state: 'Maharashtra',
);

const _homeLoadedPune = HomeLoaded(
  location: _puneHome,
  weather: _weather,
  forecast: [],
  nearbyAlerts: [],
);

// The exact archive-api.open-meteo.com/v1/archive daily shape verified
// live for this brief.
const _puneJuly2024 = ArchiveReading(
  date: '2024-07-15',
  tempMaxC: 31.2,
  tempMinC: 24.1,
  tempMeanC: 27.4,
  precipSumMm: 12.3,
  windSpeedMaxKmh: 18.2,
  windDirectionDominantDeg: 247,
);

const _puneJuly2023 = ArchiveReading(
  date: '2023-07-15',
  tempMaxC: 28.8,
  tempMinC: 22.0,
  tempMeanC: 25.0,
  precipSumMm: 5.0,
  windSpeedMaxKmh: 14.0,
  windDirectionDominantDeg: 180,
);

const _archiveWithComparison = HistoricalArchive(
  latitude: 18.5204,
  longitude: 73.8567,
  locationName: 'Pune, Maharashtra',
  reading: _puneJuly2024,
  previousYearReading: _puneJuly2023,
);

const _archiveNoComparison = HistoricalArchive(
  latitude: 18.5204,
  longitude: 73.8567,
  locationName: 'Pune, Maharashtra',
  reading: _puneJuly2024,
);

Future<void> _pumpHistorical(
  WidgetTester tester, {
  required HomeUiState homeState,
  required FakeHistoricalApi historicalApi,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeControllerProvider.overrideWith(() => _FixedHomeController(homeState)),
        historicalApiProvider.overrideWithValue(historicalApi),
      ],
      child: const MaterialApp(home: HistoricalScreen()),
    ),
  );

  // No pumpAndSettle: HistoricalLoading holds an indeterminate
  // CircularProgressIndicator, whose animation never stops — pumpAndSettle
  // would never return. Fixed pumps against the test's virtual clock are
  // deterministic instead. Mirrors aviation_screen_test.dart.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
      'opens on Home\'s current location, and shows labelled max/min/mean '
      'temperature and max wind with dominant direction', (tester) async {
    final api = FakeHistoricalApi(defaultArchive: _archiveNoComparison);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('Pune, Maharashtra'), findsOneWidget);
    expect(find.text('Max temperature'), findsOneWidget);
    expect(find.text('31.2°C'), findsOneWidget);
    expect(find.text('Min temperature'), findsOneWidget);
    expect(find.text('24.1°C'), findsOneWidget);
    expect(find.text('Mean temperature'), findsOneWidget);
    expect(find.text('27.4°C'), findsOneWidget);
    expect(find.text('Max wind'), findsOneWidget);
    // 247° -> WSW (16-point compass), 18.2 km/h rounds to 18.
    expect(find.text('WSW at 18 km/h'), findsOneWidget);
  });

  testWidgets(
      'shows a real daily precipitation total, with no "not a daily total" '
      'caveat', (tester) async {
    final api = FakeHistoricalApi(defaultArchive: _archiveNoComparison);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('12.3 mm'), findsOneWidget);
    expect(find.text('Daily total'), findsOneWidget);
    expect(
      find.textContaining('not a daily total'),
      findsNothing,
    );
    expect(find.textContaining('1-hour accumulation'), findsNothing);
  });

  testWidgets(
      'shows a same-day-different-year comparison and states the correct '
      'warmer direction and magnitude', (tester) async {
    final api = FakeHistoricalApi(defaultArchive: _archiveWithComparison);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('Same day, different year'), findsOneWidget);
    expect(find.text('15 Jul 2024'), findsWidgets);
    expect(find.text('15 Jul 2023'), findsOneWidget);
    // 27.4 - 25.0 = 2.4, current (2024) is warmer.
    expect(
      find.text('15 Jul 2024 was 2.4°C warmer than 15 Jul 2023.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'shows no comparison panel when the backend has no previous-year '
      'reading', (tester) async {
    final api = FakeHistoricalApi(defaultArchive: _archiveNoComparison);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('Same day, different year'), findsNothing);
  });

  testWidgets(
      'a 404 (no archive data for this exact date) shows the no-data '
      'state, NOT an error', (tester) async {
    final api = FakeHistoricalApi(defaultArchive: null);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('No archive reading for this date'), findsOneWidget);
    expect(find.text("Couldn't load historical data"), findsNothing);
  });

  testWidgets('a fetch failure shows the error view with a retry, not a crash',
      (tester) async {
    final api = FakeHistoricalApi(failFetch: true);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text("Couldn't load historical data"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('names ECMWF ERA5 as the data source', (tester) async {
    final api = FakeHistoricalApi(defaultArchive: _archiveNoComparison);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.textContaining('ECMWF ERA5'), findsOneWidget);
  });

  testWidgets(
      'the date picker bounds cover 1940-01-01 through 6 days before today',
      (tester) async {
    final bounds = historicalDateBounds();
    expect(bounds.first, DateTime(1940, 1, 1));

    final expectedLast = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 6));
    expect(bounds.last.year, expectedLast.year);
    expect(bounds.last.month, expectedLast.month);
    expect(bounds.last.day, expectedLast.day);
    expect(bounds.last.isBefore(DateTime.now().toUtc()), isTrue);
  });
}
