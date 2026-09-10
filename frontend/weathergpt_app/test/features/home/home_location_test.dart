import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/data/air_quality_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/nwp_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

/// Home opens on the device's own location, and degrades gracefully when
/// it cannot. A declined permission is a normal user choice, not an error:
/// the screen must still show real weather for a sensible default, and say
/// so, rather than presenting the default city as if it were "here".

const _weather = CurrentWeather(
  temperatureC: 26.0,
  humidityPct: 60,
  weatherCode: 0,
  windSpeedKmh: 8,
  windDirectionDeg: 180,
  observedAt: '2026-09-09T14:00',
  timezone: 'Asia/Kolkata',
);

class _FakeWeatherApi implements WeatherApi {
  final calls = <(double, double)>[];

  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    calls.add((lat, lon));
    return _weather;
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon,
          {int days = 5}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAlertsApi implements AlertsApi {
  @override
  Future<List<AlertSummary>> fetchAlerts() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGeocodingApi implements GeocodingApi {
  _FakeGeocodingApi({this.fail = false});

  static const name = 'Pune, Maharashtra';
  final bool fail;
  int reverseCalls = 0;

  @override
  Future<GeocodeResult?> reverse(double lat, double lon) async {
    reverseCalls++;
    if (fail) throw Exception('nominatim down');
    return GeocodeResult(
      displayName: name,
      latitude: lat,
      longitude: lon,
      country: 'India',
      state: null,
    );
  }

  @override
  Future<GeocodeResult?> search(String query) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StubLocation implements DeviceLocation {
  const _StubLocation(this.result);

  final LocationResult result;

  @override
  Future<LocationResult> current() async => result;
}

/// Air quality must be stubbed even though these tests never assert on it.
///
/// `_load` fires an air-quality request alongside the other three. Left
/// unoverridden it builds a real Dio against AppEnv's default host, which
/// is unreachable from a test, so every load sat waiting on a doomed
/// socket — enough to blow the 30s timeout once a test looped over all
/// four failure reasons.
class _FakeAirQualityApi implements AirQualityApi {
  @override
  Future<AirQuality> fetchCurrent(double lat, double lon) async =>
      const AirQuality(observedAt: '2026-09-10T14:00', usAqi: 90);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Same reasoning as [_FakeAirQualityApi]: `_load` now fetches NWP
/// alongside the others too, and an unmocked provider would build a real
/// Dio against an unreachable host.
class _FakeNwpApi implements NwpApi {
  @override
  Future<List<NwpPoint>> fetchForecast(double lat, double lon) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeWeatherApi weatherApi;
  late _FakeGeocodingApi geocodingApi;

  ProviderContainer containerWith(LocationResult location,
      {_FakeGeocodingApi? geocoding}) {
    weatherApi = _FakeWeatherApi();
    geocodingApi = geocoding ?? _FakeGeocodingApi();
    return ProviderContainer(
      overrides: [
        weatherApiProvider.overrideWithValue(weatherApi),
        alertsApiProvider.overrideWithValue(_FakeAlertsApi()),
        geocodingApiProvider.overrideWithValue(geocodingApi),
        deviceLocationProvider.overrideWithValue(_StubLocation(location)),
        airQualityApiProvider.overrideWithValue(_FakeAirQualityApi()),
        nwpApiProvider.overrideWithValue(_FakeNwpApi()),
      ],
    );
  }

  test('loadInitial fetches weather for the device position', () async {
    final container = containerWith(const LocationFixed(18.5204, 73.8567));
    addTearDown(container.dispose);

    await container.read(homeControllerProvider.notifier).loadInitial();

    // Pune, not the default Delhi.
    expect(weatherApi.calls.single, (18.5204, 73.8567));
  });

  test('names the device position via reverse geocoding', () async {
    final container = containerWith(const LocationFixed(18.5204, 73.8567));
    addTearDown(container.dispose);

    await container.read(homeControllerProvider.notifier).loadInitial();

    final state = container.read(homeControllerProvider) as HomeLoaded;
    expect(state.location.displayName, 'Pune, Maharashtra');
    expect(state.locationFailure, isNull);
  });

  test('a naming failure still shows weather for the right coordinates',
      () async {
    // Reverse geocoding is cosmetic. Losing it must not cost the fix.
    final container = containerWith(
      const LocationFixed(18.5204, 73.8567),
      geocoding: _FakeGeocodingApi(fail: true),
    );
    addTearDown(container.dispose);

    await container.read(homeControllerProvider.notifier).loadInitial();

    final state = container.read(homeControllerProvider) as HomeLoaded;
    expect(weatherApi.calls.single, (18.5204, 73.8567));
    expect(state.location.displayName, 'Current location');
    expect(state.locationFailure, isNull);
  });

  test('a denied permission falls back to the default city, not an error',
      () async {
    final container = containerWith(
      const LocationUnavailable(LocationFailure.permissionDenied),
    );
    addTearDown(container.dispose);

    await container.read(homeControllerProvider.notifier).loadInitial();

    final state = container.read(homeControllerProvider);
    // The screen still works. This is the whole point.
    expect(state, isA<HomeLoaded>());
    expect(weatherApi.calls.single, (28.6139, 77.2090));
  });

  test('records WHY the device location was not used', () async {
    // The UI offers a different remedy per reason — a retry for a plain
    // denial, a settings trip for a permanent one — so the reason has to
    // survive, not just the fact of failure.
    for (final reason in LocationFailure.values) {
      final container = containerWith(LocationUnavailable(reason));
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).loadInitial();

      final state = container.read(homeControllerProvider) as HomeLoaded;
      expect(state.locationFailure, reason, reason: '$reason');
    }
  });

  test('does not reverse geocode when there is no fix', () async {
    // Nominatim is rate-limited; a pointless lookup for a coordinate we
    // never obtained would burn quota.
    final container = containerWith(
      const LocationUnavailable(LocationFailure.serviceDisabled),
    );
    addTearDown(container.dispose);

    await container.read(homeControllerProvider.notifier).loadInitial();

    expect(geocodingApi.reverseCalls, 0);
  });

  test('choosing a location clears the failure note', () async {
    final container = containerWith(
      const LocationUnavailable(LocationFailure.permissionDenied),
    );
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    await controller.loadInitial();
    expect(
      (container.read(homeControllerProvider) as HomeLoaded).locationFailure,
      isNotNull,
    );

    await controller.changeLocation(const GeocodeResult(
      displayName: 'Bhagalpur, Bihar',
      latitude: 25.27,
      longitude: 87.23,
      country: 'India',
      state: 'Bihar',
    ));

    // The user worked around it by picking a place; nagging them about
    // location afterwards would be noise.
    final state = container.read(homeControllerProvider) as HomeLoaded;
    expect(state.locationFailure, isNull);
    expect(state.location.displayName, 'Bhagalpur, Bihar');
  });
}
