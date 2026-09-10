import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/alerts_socket.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/home/home_screen.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';

import '../../support/fake_apis.dart';

/// A user set to Nepal during real flooding there saw no alerts and
/// reasonably read that as "the app missed it". It did not: our alert
/// sources (SACHET-IMD-NOWCAST, SACHET-SDMA) are Indian government feeds
/// that do not cover Nepal — see `IndiaAlertCoverageBox`. These tests pin
/// that Home explains the silence when it means "not covered", and stays
/// quiet when it means "all clear".

const _weather = CurrentWeather(
  temperatureC: 20.0,
  humidityPct: 55,
  weatherCode: 1,
  windSpeedKmh: 10,
  windDirectionDeg: 90,
  observedAt: '2026-09-10T14:00',
  timezone: 'Asia/Kolkata',
);

class _FakeWeatherApi implements WeatherApi {
  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async => _weather;

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon,
          {int days = 5}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Always empty — every test here is about what Home shows when there is
/// genuinely nothing to report.
class _FakeAlertsApi implements AlertsApi {
  @override
  Future<List<AlertSummary>> fetchAlerts() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FixedLocation implements DeviceLocation {
  const _FixedLocation(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  Future<LocationResult> current() async => LocationFixed(latitude, longitude);
}

class _FixedGeocoding implements GeocodingApi {
  const _FixedGeocoding(this.result);

  final GeocodeResult result;

  @override
  Future<GeocodeResult?> reverse(double lat, double lon) async => result;

  @override
  Future<GeocodeResult?> search(String query) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _SilentSocket implements AlertsSocket {
  @override
  Stream<List<AlertSummary>> get newAlerts => const Stream.empty();

  @override
  void dispose() {}
}

const _paris = GeocodeResult(
  displayName: 'Paris, France',
  latitude: 48.8566,
  longitude: 2.3522,
  country: 'France',
  state: null,
);

const _delhi = GeocodeResult(
  displayName: 'New Delhi, India',
  latitude: 28.6139,
  longitude: 77.2090,
  country: 'India',
  state: 'Delhi',
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required GeocodeResult location,
  List<AlertSummary> alerts = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherApiProvider.overrideWithValue(_FakeWeatherApi()),
        alertsApiProvider.overrideWithValue(
          alerts.isEmpty ? _FakeAlertsApi() : _AlertsWith(alerts),
        ),
        airQualityApiProvider.overrideWithValue(FakeAirQualityApi()),
        nwpApiProvider.overrideWithValue(FakeNwpApi()),
        deviceLocationProvider
            .overrideWithValue(_FixedLocation(location.latitude, location.longitude)),
        geocodingApiProvider.overrideWithValue(_FixedGeocoding(location)),
        alertsSocketProvider.overrideWithValue(_SilentSocket()),
        savedPlacesStoreProvider.overrideWithValue(FakeSavedPlacesStore()),
        conversationStoreProvider.overrideWithValue(FakeConversationStore()),
      ],
      child: MaterialApp(home: HomeScreen(now: DateTime(2026, 9, 10, 14))),
    ),
  );

  // No pumpAndSettle: HomeLoading holds an indeterminate
  // CircularProgressIndicator, whose animation never stops — pumpAndSettle
  // would never return. Fixed pumps against the test's virtual clock are
  // deterministic instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

class _AlertsWith implements AlertsApi {
  _AlertsWith(this.alerts);
  final List<AlertSummary> alerts;

  @override
  Future<List<AlertSummary>> fetchAlerts() async => alerts;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _coverageNote = 'Alerts cover India only, sourced from IMD/SACHET.';

void main() {
  testWidgets(
      'an out-of-India location with no nearby alerts explains the '
      'coverage gap instead of reading as a missed alert', (tester) async {
    await _pumpHome(tester, location: _paris);

    expect(find.text(_coverageNote), findsOneWidget);
  });

  testWidgets(
      'an in-India location with no nearby alerts stays quiet — silence '
      'there already means "all clear"', (tester) async {
    await _pumpHome(tester, location: _delhi);

    expect(find.text(_coverageNote), findsNothing);
  });

  testWidgets(
      'a real nearby alert is shown and the coverage note does not also '
      'appear alongside it', (tester) async {
    const alert = AlertSummary(
      id: 1,
      severity: 'Orange',
      eventType: 'Heavy Rain',
      areaDescription: 'Delhi NCR',
      latitude: 28.61,
      longitude: 77.21,
    );
    await _pumpHome(tester, location: _delhi, alerts: const [alert]);

    expect(find.text('Heavy Rain'), findsOneWidget);
    expect(find.text(_coverageNote), findsNothing);
  });
}
