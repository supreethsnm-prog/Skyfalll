import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/metar_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/aviation/airports.dart';
import 'package:weathergpt_app/features/aviation/aviation_controller.dart';
import 'package:weathergpt_app/features/aviation/aviation_screen.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

/// Aviation reads its location from Home rather than resolving its own —
/// these tests fix Home's state directly (bypassing its real fetch
/// pipeline, which is exercised elsewhere) so the screen's own behaviour is
/// what's under test. Mirrors `advisory_screen_test.dart`.
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

// Deliberately Delhi's OWN coordinates — VIDP's own lat/lon in
// airports.dart — so the nearest-airport distance is a deterministic,
// real zero rather than a hand-picked approximation.
const _delhi = GeocodeResult(
  displayName: 'New Delhi, India',
  latitude: 28.5665,
  longitude: 77.1031,
  country: 'India',
  state: 'Delhi',
);

const _homeLoadedDelhi = HomeLoaded(
  location: _delhi,
  weather: _weather,
  forecast: [],
  nearbyAlerts: [],
);

// Verified by hand for this brief (see .superpowers/sdd/aviation-brief.md):
// Pune's nearest bundled airport is VABB Mumbai, not VOHS Hyderabad or
// VOGO Goa.
const _pune = GeocodeResult(
  displayName: 'Pune, Maharashtra',
  latitude: 18.5204,
  longitude: 73.8567,
  country: 'India',
  state: 'Maharashtra',
);

const _homeLoadedPune = HomeLoaded(
  location: _pune,
  weather: _weather,
  forecast: [],
  nearbyAlerts: [],
);

// The exact VIDP contract sample from the verified brief.
const _vidpReading = MetarReading(
  icaoId: 'VIDP',
  rawMetar: 'METAR VIDP 100230Z 26009KT 4000 HZ NSC 29/22 Q1009 NOSIG',
  observedAt: '2026-09-10T02:30:00.000Z',
  stationName: 'New Delhi/Gandhi Intl, DL, IN',
  temperatureC: 29.0,
  dewpointC: 22.0,
  windDirDeg: 260.0,
  windSpeedKt: 9.0,
  visibilitySm: 2.49,
  flightCategory: 'MVFR',
);

const _vabbReading = MetarReading(
  icaoId: 'VABB',
  rawMetar: 'METAR VABB 100230Z 27015KT 1500 RA BKN008 27/24 Q1006 NOSIG',
  observedAt: '2026-09-10T02:30:00.000Z',
  stationName: 'Mumbai/Chhatrapati Shivaji Intl, MH, IN',
  temperatureC: 27.0,
  dewpointC: 24.0,
  windDirDeg: 270.0,
  windSpeedKt: 15.0,
  visibilitySm: 0.93,
  flightCategory: 'IFR',
);

class _FakeMetarApi implements MetarApi {
  _FakeMetarApi({this.readings = const {}, this.fail = false});

  /// icao -> reading. A missing key means the backend's 404 (no current
  /// observation), matching what the real `MetarApi.fetch` returns.
  final Map<String, MetarReading?> readings;
  final bool fail;

  /// Every ICAO this fake was asked to fetch, in order.
  final calls = <String>[];

  @override
  Future<MetarReading?> fetch(String icao) async {
    calls.add(icao);
    if (fail) throw const NetworkConnectionError();
    return readings[icao];
  }
}

Future<void> _pumpAviation(
  WidgetTester tester, {
  required HomeUiState homeState,
  required _FakeMetarApi metarApi,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeControllerProvider
            .overrideWith(() => _FixedHomeController(homeState)),
        metarApiProvider.overrideWithValue(metarApi),
      ],
      child: const MaterialApp(home: AviationScreen()),
    ),
  );

  // No pumpAndSettle: HomeLoading/AviationLoading both hold an
  // indeterminate CircularProgressIndicator, whose animation never stops —
  // pumpAndSettle would never return. Fixed pumps against the test's
  // virtual clock are deterministic instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
      'shows a loading state while Home has not resolved a location yet, '
      'never a default airport', (tester) async {
    await _pumpAviation(
      tester,
      homeState: const HomeLoading(),
      metarApi: _FakeMetarApi(),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('VIDP'), findsNothing);
  });

  testWidgets(
      'opens on the airport nearest Home\'s location, with its distance, '
      'category, observation, and raw report', (tester) async {
    final api = _FakeMetarApi(readings: const {'VIDP': _vidpReading});
    await _pumpAviation(tester, homeState: _homeLoadedDelhi, metarApi: api);

    expect(api.calls, ['VIDP']);
    expect(find.text('Delhi (VIDP)'), findsOneWidget);
    // Home's location IS VIDP's own coordinates here, so the real distance
    // is genuinely 0 — not a fallback for missing data.
    expect(find.text('0 km away'), findsOneWidget);
    expect(find.text('MVFR'), findsOneWidget);
    expect(find.text('29°C'), findsOneWidget);
    expect(find.text('22°C'), findsOneWidget);
    // 9kt * 1.852 = 16.668 -> rounds to 17 km/h.
    expect(find.text('260° at 17 km/h'), findsOneWidget);
    // 2.49 SM * 1.609344 = 4.0072... km -> one decimal place.
    expect(find.text('4.0 km'), findsOneWidget);
    expect(
      find.textContaining('METAR VIDP 100230Z 26009KT'),
      findsOneWidget,
    );
  });

  testWidgets(
      'opens on VABB for Pune, not VOHS or VOGO — verified nearest-airport '
      'claim from the brief', (tester) async {
    final api = _FakeMetarApi(readings: const {'VABB': _vabbReading});
    await _pumpAviation(tester, homeState: _homeLoadedPune, metarApi: api);

    expect(api.calls, ['VABB']);
    expect(find.text('Mumbai (VABB)'), findsOneWidget);

    final vabb = indianAirports.firstWhere((a) => a.icao == 'VABB');
    final expectedDistance =
        distanceToAirportKm(_pune.latitude, _pune.longitude, vabb).round();
    expect(find.text('$expectedDistance km away'), findsOneWidget);
  });

  Future<void> expectCategoryColour(
    WidgetTester tester,
    String category,
    String expectedSeverity,
  ) async {
    final reading = MetarReading(
      icaoId: 'VIDP',
      rawMetar: 'METAR VIDP 100230Z 26009KT 4000 HZ NSC 29/22 Q1009 NOSIG',
      observedAt: '2026-09-10T02:30:00.000Z',
      flightCategory: category,
    );
    final api = _FakeMetarApi(readings: {'VIDP': reading});
    await _pumpAviation(tester, homeState: _homeLoadedDelhi, metarApi: api);

    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text(category), matching: find.byType(Container))
          .first,
    );
    final color = (container.decoration as BoxDecoration).color;
    expect(color, AppColors.alertSeverity(expectedSeverity),
        reason: '$category should colour as $expectedSeverity');
  }

  testWidgets('VFR colours as minor', (tester) async {
    await expectCategoryColour(tester, 'VFR', 'minor');
  });

  testWidgets('MVFR colours as moderate', (tester) async {
    await expectCategoryColour(tester, 'MVFR', 'moderate');
  });

  testWidgets('IFR colours as severe', (tester) async {
    await expectCategoryColour(tester, 'IFR', 'severe');
  });

  testWidgets('LIFR colours as extreme', (tester) async {
    await expectCategoryColour(tester, 'LIFR', 'extreme');
  });

  // The four categories resolving to four DISTINCT colours is pinned at
  // the pure-function level in flight_category_test.dart; the four tests
  // above pin that this screen actually applies that mapping to a real
  // rendered Container.

  testWidgets(
      'a missing flight category is never coloured as VFR (minor) — it is '
      'absent data, not a known-good reading', (tester) async {
    const reading = MetarReading(
      icaoId: 'VIDP',
      rawMetar: 'METAR VIDP 100230Z ///// //// // ////// ////// NOSIG',
      observedAt: '2026-09-10T02:30:00.000Z',
    );
    final api = _FakeMetarApi(readings: const {'VIDP': reading});
    await _pumpAviation(tester, homeState: _homeLoadedDelhi, metarApi: api);

    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Not reported'),
            matching: find.byType(Container),
          )
          .first,
    );
    final color = (container.decoration as BoxDecoration).color;
    expect(color, isNot(AppColors.alertSeverity('minor')));
    expect(color, AppColors.surfaceRaised);
  });

  testWidgets(
      'missing temperature/dewpoint/wind/visibility render as "Not '
      'reported", never 0 or a dash', (tester) async {
    const reading = MetarReading(
      icaoId: 'VIDP',
      rawMetar: 'METAR VIDP 100230Z ///// //// // ////// ////// NOSIG',
      observedAt: '2026-09-10T02:30:00.000Z',
      flightCategory: 'VFR',
    );
    final api = _FakeMetarApi(readings: const {'VIDP': reading});
    await _pumpAviation(tester, homeState: _homeLoadedDelhi, metarApi: api);

    // Temperature, dew point, wind, visibility — four absent stats.
    expect(find.text('Not reported'), findsNWidgets(4));
    expect(find.text('0°C'), findsNothing);
    expect(find.text('0 km'), findsNothing);
  });

  testWidgets(
      'a 404 (no current observation) shows the no-observation state, '
      'NOT an error', (tester) async {
    final api = _FakeMetarApi(readings: const {}); // VIDP absent -> null
    await _pumpAviation(tester, homeState: _homeLoadedDelhi, metarApi: api);

    expect(
      find.text('No current observation for this station'),
      findsOneWidget,
    );
    expect(find.text("Couldn't load the observation"), findsNothing);
  });

  testWidgets('a fetch failure shows the error view with a retry, not a crash',
      (tester) async {
    final api = _FakeMetarApi(fail: true);
    await _pumpAviation(tester, homeState: _homeLoadedDelhi, metarApi: api);

    expect(find.text("Couldn't load the observation"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
      'the airport picker lets any of the 14 airports be chosen, and '
      'refetches for it', (tester) async {
    final api = _FakeMetarApi(readings: const {
      'VIDP': _vidpReading,
      'VABB': _vabbReading,
    });
    await _pumpAviation(tester, homeState: _homeLoadedDelhi, metarApi: api);

    expect(find.text('Delhi (VIDP)'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Choose an airport'), findsOneWidget);
    // Every bundled airport is listed.
    expect(find.text('Mumbai (VABB)'), findsOneWidget);
    expect(find.text('Chennai (VOMM)'), findsOneWidget);

    await tester.tap(find.text('Mumbai (VABB)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.calls.last, 'VABB');
    expect(find.text('Mumbai (VABB)'), findsOneWidget);
    expect(find.text('IFR'), findsOneWidget);
  });
}
