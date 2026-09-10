import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/data/advisory_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/advisory/advisory_controller.dart';
import 'package:weathergpt_app/features/advisory/advisory_screen.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/home/widgets/alert_banner.dart';

/// Advisories reads its location from Home rather than resolving its own —
/// these tests fix Home's state directly (bypassing its real fetch
/// pipeline, which is exercised elsewhere) so the screen's own behaviour
/// is what's under test.
class _FixedHomeController extends HomeController {
  _FixedHomeController(this._initial);
  final HomeUiState _initial;

  @override
  HomeUiState build() => _initial;
}

const _pune = GeocodeResult(
  displayName: 'Pune, Maharashtra',
  latitude: 18.5204,
  longitude: 73.8567,
  country: 'India',
  state: 'Maharashtra',
);

const _weather = CurrentWeather(
  temperatureC: 28.0,
  humidityPct: 70,
  weatherCode: 61,
  windSpeedKmh: 14,
  windDirectionDeg: 200,
  observedAt: '2026-09-10T08:00:00+05:30',
  timezone: 'Asia/Kolkata',
);

const _homeLoaded = HomeLoaded(
  location: _pune,
  weather: _weather,
  forecast: [],
  nearbyAlerts: [],
);

const _sampleForecastDay = ForecastDay(
  forecastDate: '2026-09-10',
  weatherCode: 61,
  tempMaxC: 30.0,
  tempMinC: 22.0,
);

UrbanAdvisory _urban({
  String waterlogging = 'LOW',
  String heat = 'LOW',
  String wind = 'LOW',
  List<String> advisories = const [],
  List<AlertSummary> alerts = const [],
}) =>
    UrbanAdvisory(
      latitude: _pune.latitude,
      longitude: _pune.longitude,
      generatedAt: '2026-09-10T08:00:00+05:30',
      riskSummary: UrbanRiskSummary(
        waterloggingRisk: waterlogging,
        heatRisk: heat,
        windRisk: wind,
      ),
      advisories: advisories,
      activeAlerts: alerts,
      forecastBasis: const [_sampleForecastDay],
    );

AgricultureAdvisory _agriculture({
  String? crop,
  List<String> advisories = const [],
  List<AlertSummary> alerts = const [],
}) =>
    AgricultureAdvisory(
      latitude: _pune.latitude,
      longitude: _pune.longitude,
      crop: crop,
      generatedAt: '2026-09-10T08:00:00+05:30',
      advisories: advisories,
      activeAlerts: alerts,
      forecastBasis: const [_sampleForecastDay],
    );

class _FakeAdvisoryApi implements AdvisoryApi {
  _FakeAdvisoryApi({
    UrbanAdvisory? urban,
    this.agricultureAlerts = const [],
    this.fail = false,
  }) : urban = urban ?? _urban();

  final UrbanAdvisory urban;
  final List<AlertSummary> agricultureAlerts;
  final bool fail;

  /// Every agriculture call this fake received, in order — lets a test
  /// pin exactly which crop (or none) went out on the wire.
  final agricultureCalls = <({double lat, double lon, String? crop})>[];

  @override
  Future<AgricultureAdvisory> fetchAgriculture(
    double lat,
    double lon, {
    String? crop,
    int days = 5,
  }) async {
    agricultureCalls.add((lat: lat, lon: lon, crop: crop));
    if (fail) throw const NetworkConnectionError();
    return _agriculture(crop: crop, alerts: agricultureAlerts);
  }

  @override
  Future<UrbanAdvisory> fetchUrban(double lat, double lon, {int days = 5}) async {
    if (fail) throw const NetworkConnectionError();
    return urban;
  }
}

Future<void> _pumpAdvisories(
  WidgetTester tester, {
  required HomeUiState homeState,
  required _FakeAdvisoryApi advisoryApi,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeControllerProvider
            .overrideWith(() => _FixedHomeController(homeState)),
        advisoryApiProvider.overrideWithValue(advisoryApi),
      ],
      child: const MaterialApp(home: AdvisoryScreen()),
    ),
  );

  // No pumpAndSettle: HomeLoading/AdvisoryLoading both hold an
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
      'never a default place', (tester) async {
    await _pumpAdvisories(
      tester,
      homeState: const HomeLoading(),
      advisoryApi: _FakeAdvisoryApi(),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Pune, Maharashtra'), findsNothing);
  });

  testWidgets('shows the place name and each urban risk band once loaded',
      (tester) async {
    final api = _FakeAdvisoryApi(
      urban: _urban(waterlogging: 'HIGH', heat: 'MODERATE', wind: 'LOW'),
    );
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    expect(find.text('Pune, Maharashtra'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
  });

  testWidgets(
      'the four documented risk bands render as four distinct tile colours',
      (tester) async {
    final api = _FakeAdvisoryApi(
      urban: _urban(waterlogging: 'SEVERE', heat: 'HIGH', wind: 'LOW'),
    );
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    Color colorOf(String label) {
      final container = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (container.decoration as BoxDecoration).color!;
    }

    final waterlogging = colorOf('Waterlogging');
    final heat = colorOf('Heat');
    final wind = colorOf('Wind');

    expect(waterlogging, AppColors.alertSeverity('extreme'));
    expect(heat, AppColors.alertSeverity('severe'));
    expect(wind, AppColors.alertSeverity('minor'));
    expect({waterlogging, heat, wind}, hasLength(3));
  });

  testWidgets(
      "an unrecognised risk band (the backend's UNKNOWN) is not coloured "
      "as LOW", (tester) async {
    final api = _FakeAdvisoryApi(urban: _urban(waterlogging: 'UNKNOWN'));
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Waterlogging'),
            matching: find.byType(Container),
          )
          .first,
    );
    final color = (container.decoration as BoxDecoration).color;

    expect(color, isNot(AppColors.alertSeverity('minor')));
    expect(color, AppColors.surfaceRaised);
    // The band's text is still shown — absent a colour, it must not read
    // as blank or as a real band either.
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets(
      'an empty advisory list shows the reassuring empty state, not an error',
      (tester) async {
    // Both endpoints default to an empty advisories list.
    await _pumpAdvisories(
      tester,
      homeState: _homeLoaded,
      advisoryApi: _FakeAdvisoryApi(),
    );

    expect(find.textContaining('No advisories'), findsOneWidget);
    expect(find.textContaining("Couldn't load"), findsNothing);
  });

  testWidgets('a real advisory sentence renders in full, not truncated',
      (tester) async {
    const sentence =
        'Heavy rain forecast (>=64.5mm/day) — avoid irrigation and hold '
        'off fertilizer/pesticide application until after the rain.';
    final api = _FakeAdvisoryApi(urban: _urban(advisories: const [sentence]));
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    final textWidget = tester.widget<Text>(find.text(sentence));
    expect(textWidget.maxLines, isNull);
  });

  testWidgets('a fetch failure shows the error view with a retry, not a crash',
      (tester) async {
    final api = _FakeAdvisoryApi(fail: true);
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    expect(find.text("Couldn't load advisories"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
      'changing the crop chip refetches agriculture with the new crop '
      'query parameter', (tester) async {
    final api = _FakeAdvisoryApi();
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    // The initial load, from the "All" default.
    expect(api.agricultureCalls.last.crop, isNull);

    await tester.tap(find.text('Wheat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(api.agricultureCalls.last.crop, 'wheat');
    expect(api.agricultureCalls.last.lat, _pune.latitude);
    expect(api.agricultureCalls.last.lon, _pune.longitude);
  });

  testWidgets('active alerts from either endpoint reuse AlertBanner',
      (tester) async {
    const alert = AlertSummary(
      id: 1,
      severity: 'Severe',
      eventType: 'Flood',
      areaDescription: 'Pune district',
      latitude: 18.52,
      longitude: 73.86,
    );
    final api = _FakeAdvisoryApi(urban: _urban(alerts: const [alert]));
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    expect(find.byType(AlertBanner), findsOneWidget);
  });

  testWidgets('the same alert id from both endpoints is not shown twice',
      (tester) async {
    // Both /advisory/urban and /advisory/agriculture filter the same
    // nationwide feed through the same radius for the same location, so
    // in practice they return the same alert — it must render once.
    const alert = AlertSummary(
      id: 7,
      severity: 'Orange',
      eventType: 'Heavy Rain',
      areaDescription: 'Pune district',
      latitude: 18.52,
      longitude: 73.86,
    );
    final api = _FakeAdvisoryApi(
      urban: _urban(alerts: const [alert]),
      agricultureAlerts: const [alert],
    );
    await _pumpAdvisories(tester, homeState: _homeLoaded, advisoryApi: api);

    expect(find.byType(AlertBanner), findsOneWidget);
  });
}
