import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

/// Alerts pushed over the socket must obey the SAME radius rule as
/// fetched ones. A live warning for Kerala appearing on a Delhi screen
/// would be worse than no live alerts at all — on a disaster app, a
/// warning that does not apply to you teaches you to ignore warnings.

AlertSummary _alert({
  required int id,
  required double lat,
  required double lon,
  String severity = 'Orange',
}) =>
    AlertSummary(
      id: id,
      severity: severity,
      eventType: 'Flood',
      areaDescription: 'Test area',
      latitude: lat,
      longitude: lon,
    );

class _FakeWeatherApi implements WeatherApi {
  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async =>
      const CurrentWeather(
        temperatureC: 26,
        humidityPct: 60,
        weatherCode: 0,
        windSpeedKmh: 8,
        windDirectionDeg: 180,
        observedAt: '2026-09-09T14:00',
        timezone: 'Asia/Kolkata',
      );

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon,
          {int days = 5}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAlertsApi implements AlertsApi {
  _FakeAlertsApi([this.alerts = const []]);
  final List<AlertSummary> alerts;

  @override
  Future<List<AlertSummary>> fetchAlerts() async => alerts;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoFix implements DeviceLocation {
  const _NoFix();

  @override
  Future<LocationResult> current() async =>
      const LocationUnavailable(LocationFailure.permissionDenied);
}

Future<HomeController> _loadedController({
  List<AlertSummary> initial = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      weatherApiProvider.overrideWithValue(_FakeWeatherApi()),
      alertsApiProvider.overrideWithValue(_FakeAlertsApi(initial)),
      deviceLocationProvider.overrideWithValue(const _NoFix()),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(homeControllerProvider.notifier);
  // Falls back to Delhi, which every distance below is measured from.
  await controller.loadInitial();
  return controller;
}

void main() {
  test('adds a nearby pushed alert and reports it', () async {
    final controller = await _loadedController();

    // ~20km from Delhi centre.
    final added = controller.mergeLiveAlerts([
      _alert(id: 1, lat: 28.75, lon: 77.30),
    ]);

    expect(added, hasLength(1));
    final state = controller.state as HomeLoaded;
    expect(state.nearbyAlerts.single.id, 1);
  });

  test('ignores a pushed alert outside the radius', () async {
    final controller = await _loadedController();

    // Kerala — roughly 2000km away.
    final added = controller.mergeLiveAlerts([
      _alert(id: 2, lat: 10.85, lon: 76.27),
    ]);

    expect(added, isEmpty);
    expect((controller.state as HomeLoaded).nearbyAlerts, isEmpty);
  });

  test('reports nothing when every pushed alert is far away', () async {
    // The UI announces only what merge returns, so an empty return is
    // what keeps a distant batch from interrupting the user.
    final controller = await _loadedController();

    final added = controller.mergeLiveAlerts([
      _alert(id: 2, lat: 10.85, lon: 76.27),
      _alert(id: 3, lat: 19.07, lon: 72.87),
    ]);

    expect(added, isEmpty);
  });

  test('ignores an alert with no coordinates', () async {
    final controller = await _loadedController();

    final added = controller.mergeLiveAlerts([
      const AlertSummary(
        id: 4,
        severity: 'Orange',
        eventType: 'Flood',
        areaDescription: 'Nowhere',
        latitude: null,
        longitude: null,
      ),
    ]);

    expect(added, isEmpty);
  });

  test('does not duplicate an alert already on screen', () async {
    // Ingestion can re-broadcast; the same warning must not stack up.
    final existing = _alert(id: 5, lat: 28.70, lon: 77.25);
    final controller = await _loadedController(initial: [existing]);

    expect((controller.state as HomeLoaded).nearbyAlerts, hasLength(1));

    final added = controller.mergeLiveAlerts([existing]);

    expect(added, isEmpty);
    expect((controller.state as HomeLoaded).nearbyAlerts, hasLength(1));
  });

  test('puts the newest alert first', () async {
    final older = _alert(id: 6, lat: 28.70, lon: 77.25);
    final controller = await _loadedController(initial: [older]);

    controller.mergeLiveAlerts([_alert(id: 7, lat: 28.72, lon: 77.26)]);

    // A warning that just arrived is the one to read.
    final state = controller.state as HomeLoaded;
    expect(state.nearbyAlerts.map((a) => a.id), [7, 6]);
  });

  test('is a no-op before the screen has loaded', () async {
    final container = ProviderContainer(
      overrides: [
        weatherApiProvider.overrideWithValue(_FakeWeatherApi()),
        alertsApiProvider.overrideWithValue(_FakeAlertsApi()),
        deviceLocationProvider.overrideWithValue(const _NoFix()),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    // Still HomeLoading — a push arriving now has no location to filter
    // against and must not invent a loaded state.
    final added = controller.mergeLiveAlerts([
      _alert(id: 8, lat: 28.70, lon: 77.25),
    ]);

    expect(added, isEmpty);
    expect(controller.state, isA<HomeLoading>());
  });
}
