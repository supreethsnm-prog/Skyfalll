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

/// Historical prefers Home's current location among whatever coverage
/// offers, so these tests fix Home's state directly, mirroring
/// `aviation_screen_test.dart`.
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

const _chennaiHome = GeocodeResult(
  displayName: 'Chennai, Tamil Nadu',
  latitude: 13.0827,
  longitude: 80.2707,
  country: 'India',
  state: 'Tamil Nadu',
);

const _homeLoadedChennai = HomeLoaded(
  location: _chennaiHome,
  weather: _weather,
  forecast: [],
  nearbyAlerts: [],
);

// The exact /historical/available shape verified live for this brief (see
// .superpowers/sdd/historical-brief.md): three cities, each with the same
// three sample dates, dates sorted newest first.
const _bhagalpur = HistoricalCoverage(
  locationName: 'Bhagalpur',
  latitude: 25.27,
  longitude: 87.23,
  dates: ['2024-07-15', '2024-01-15', '2023-07-15'],
);

const _newDelhi = HistoricalCoverage(
  locationName: 'New Delhi',
  latitude: 28.61,
  longitude: 77.21,
  dates: ['2024-07-15', '2024-01-15', '2023-07-15'],
);

const _pune = HistoricalCoverage(
  locationName: 'Pune',
  latitude: 18.52,
  longitude: 73.86,
  dates: ['2024-07-15', '2024-01-15', '2023-07-15'],
);

const _coverage = [_bhagalpur, _newDelhi, _pune];

// The exact /historical Pune/2024-07-15 contract sample from the verified
// brief.
const _puneJuly2024 = HistoricalReading(
  locationName: 'Pune',
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

const _puneJuly2023 = HistoricalReading(
  locationName: 'Pune',
  latitude: 18.52,
  longitude: 73.86,
  observationDate: '2023-07-15',
  temp2mC: 23.0,
  dewpoint2mC: 20.0,
  precipMm: 0.05,
  windSpeed10mKmh: 5.0,
  windDirection10mDeg: 180.0,
  mslpHpa: 1005.0,
);

const _puneJan2024 = HistoricalReading(
  locationName: 'Pune',
  latitude: 18.52,
  longitude: 73.86,
  observationDate: '2024-01-15',
  temp2mC: 18.0,
  dewpoint2mC: 10.0,
  precipMm: 0.0,
  windSpeed10mKmh: 12.0,
  windDirection10mDeg: 300.0,
  mslpHpa: 1015.0,
);

const _bhagalpurJuly2024 = HistoricalReading(
  locationName: 'Bhagalpur',
  latitude: 25.27,
  longitude: 87.23,
  observationDate: '2024-07-15',
  temp2mC: 30.0,
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
  testWidgets('an empty coverage list shows "no historical data loaded", '
      'not an error', (tester) async {
    final api = FakeHistoricalApi(coverage: const []);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('No historical data loaded'), findsOneWidget);
    expect(find.text("Couldn't load historical data"), findsNothing);
  });

  testWidgets(
      'opens on the location matching Home\'s current location, even when '
      "it isn't first in the coverage response", (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {'Pune|2024-07-15': _puneJuly2024},
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('Pune'), findsOneWidget);
    // Newest date first, per the backend's own sort.
    expect(find.text('15 Jul 2024'), findsWidgets);
  });

  testWidgets(
      "falls back to the coverage's first entry when Home's location isn't "
      'covered', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {'Bhagalpur|2024-07-15': _bhagalpurJuly2024},
    );
    await _pumpHistorical(
        tester, homeState: _homeLoadedChennai, historicalApi: api);

    expect(find.text('Bhagalpur'), findsOneWidget);
  });

  testWidgets(
      'shows labelled temperature, dew point, pressure, and wind with '
      'cardinal direction', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {'Pune|2024-07-15': _puneJuly2024},
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('25.4°C'), findsOneWidget);
    expect(find.text('Dew point'), findsOneWidget);
    expect(find.text('22.6°C'), findsOneWidget);
    expect(find.text('Pressure (MSLP)'), findsOneWidget);
    expect(find.text('1002 hPa'), findsOneWidget);
    expect(find.text('Wind'), findsOneWidget);
    // 262.87° -> W (16-point compass: 262.87/22.5 = 11.68, rounds to 12 ->
    // 'W'), 8.73 km/h rounds to 9.
    expect(find.text('W at 9 km/h'), findsOneWidget);
  });

  testWidgets(
      'precipitation is labelled as an hourly figure at 12:00 UTC, NEVER '
      'as a daily total', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {'Pune|2024-07-15': _puneJuly2024},
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    // 0.18262863159179688 rounded to 2dp.
    expect(find.text('0.18 mm'), findsOneWidget);
    expect(
      find.text('1-hour accumulation ending 12:00 UTC — not a daily total'),
      findsOneWidget,
    );
    // The single worst mistake available in this task: never say this is a
    // day's rainfall total.
    expect(find.textContaining('rainfall today'), findsNothing);
    expect(find.textContaining("today's rainfall"), findsNothing);
  });

  testWidgets(
      'shows a same-month-day comparison and states the correct warmer '
      'direction and magnitude', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {
        'Pune|2024-07-15': _puneJuly2024,
        'Pune|2023-07-15': _puneJuly2023,
      },
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('Same day, different year'), findsOneWidget);
    expect(find.text('15 Jul 2024'), findsWidgets);
    expect(find.text('15 Jul 2023'), findsOneWidget);
    // 25.4 - 23.0 = 2.4, current (2024) is warmer.
    expect(
      find.text('15 Jul 2024 was 2.4°C warmer than 15 Jul 2023.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'shows no comparison when no other date shares the same month-day — '
      'never invents one from an unrelated date', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {
        'Pune|2024-07-15': _puneJuly2024,
        'Pune|2024-01-15': _puneJan2024,
      },
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    // Switch to 15 Jan 2024, which has no matching month-day in the
    // coverage's other two dates (both 15 July).
    await tester.tap(find.text('Change date'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('15 Jan 2024'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('18.0°C'), findsOneWidget);
    expect(find.text('Same day, different year'), findsNothing);
  });

  testWidgets(
      'a 404 for the selected pair shows the no-data state, NOT an error',
      (tester) async {
    final api = FakeHistoricalApi(
      coverage: const [_pune],
      readings: const {}, // Pune|2024-07-15 absent -> null -> 404
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('No ERA5 reading for this date'), findsOneWidget);
    expect(find.text("Couldn't load historical data"), findsNothing);
  });

  testWidgets('a fetch failure shows the error view with a retry, not a crash',
      (tester) async {
    final api = FakeHistoricalApi(coverage: _coverage, failFetch: true);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text("Couldn't load historical data"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
      'a coverage-fetch failure also shows the error view with a retry',
      (tester) async {
    final api = FakeHistoricalApi(failAvailable: true);
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text("Couldn't load historical data"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
      'the location picker offers only locations from the coverage response, '
      'and refetches when one is chosen', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {
        'Pune|2024-07-15': _puneJuly2024,
        'Bhagalpur|2024-07-15': _bhagalpurJuly2024,
      },
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.text('Pune'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Choose a location'), findsOneWidget);
    expect(find.text('Bhagalpur'), findsOneWidget);
    expect(find.text('New Delhi'), findsOneWidget);

    await tester.tap(find.text('Bhagalpur'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Bhagalpur'), findsOneWidget);
    expect(find.text('30.0°C'), findsOneWidget);
  });

  testWidgets(
      'the date picker offers only dates from the SELECTED location\'s own '
      'coverage, and refetches when one is chosen', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {
        'Pune|2024-07-15': _puneJuly2024,
        'Pune|2024-01-15': _puneJan2024,
        'Pune|2023-07-15': _puneJuly2023,
      },
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    await tester.tap(find.text('Change date'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Choose a date'), findsOneWidget);
    expect(find.text('15 Jul 2024'), findsWidgets);
    expect(find.text('15 Jan 2024'), findsOneWidget);
    // Also rendered by the comparison section below the (still-mounted)
    // sheet, since 2023-07-15 is 2024-07-15's same-month-day partner and
    // both readings are present in this test's fixture.
    expect(find.text('15 Jul 2023'), findsWidgets);

    await tester.tap(find.text('15 Jan 2024'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('18.0°C'), findsOneWidget);
  });

  testWidgets('names ECMWF ERA5 as the data source', (tester) async {
    final api = FakeHistoricalApi(
      coverage: _coverage,
      readings: const {'Pune|2024-07-15': _puneJuly2024},
    );
    await _pumpHistorical(tester, homeState: _homeLoadedPune, historicalApi: api);

    expect(find.textContaining('ECMWF ERA5'), findsOneWidget);
  });
}
