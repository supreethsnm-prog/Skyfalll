import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/nwp_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

/// Reports no fix, so the controller falls back to its default city.
class _NoDeviceFix implements DeviceLocation {
  const _NoDeviceFix();

  @override
  Future<LocationResult> current() async =>
      const LocationUnavailable(LocationFailure.permissionDenied);
}

const _sampleWeather = CurrentWeather(
  temperatureC: 32.0,
  humidityPct: 40.0,
  weatherCode: 0,
  windSpeedKmh: 10.0,
  windDirectionDeg: 90.0,
  observedAt: '2026-09-09T10:00:00Z',
  timezone: 'Asia/Kolkata',
);

const _sampleForecast = [
  ForecastDay(forecastDate: '2026-09-10', weatherCode: 61, tempMaxC: 30.0, tempMinC: 22.0),
];

// A real Delhi-area coordinate (well within 100km) and a real,
// clearly-far-away coordinate (Chennai, ~1750km from Delhi) so the
// distance filtering test exercises genuinely different outcomes.
const _nearbyAlert = AlertSummary(
  id: 1,
  severity: 'Moderate',
  eventType: 'Heatwave',
  areaDescription: 'Delhi NCR',
  latitude: 28.7,
  longitude: 77.1,
);
const _farAlert = AlertSummary(
  id: 2,
  severity: 'Severe',
  eventType: 'Flood',
  areaDescription: 'Chennai',
  latitude: 13.0827,
  longitude: 80.2707,
);
const _noCoordsAlert = AlertSummary(
  id: 3,
  severity: 'Minor',
  eventType: 'Fog',
  areaDescription: null,
  latitude: null,
  longitude: null,
);

class FakeWeatherApi implements WeatherApi {
  CurrentWeather? nextWeather;
  AppError? nextWeatherError;
  final List<List<double>> fetchCurrentCalls = [];

  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    fetchCurrentCalls.add([lat, lon]);
    if (nextWeatherError != null) throw nextWeatherError!;
    return nextWeather!;
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon, {int days = 5}) async {
    return _sampleForecast;
  }
}

class FakeAlertsApi implements AlertsApi {
  List<AlertSummary> nextAlerts = const [];

  @override
  Future<List<AlertSummary>> fetchAlerts() async => nextAlerts;
}

const _sampleNwp = [
  NwpPoint(
    runDate: '20260909',
    runHour: '18',
    forecastHour: 0,
    validTime: '2026-09-09T18:00:00Z',
    capeJPerKg: 1500,
  ),
];

class FakeNwpApi implements NwpApi {
  List<NwpPoint> nextNwp = _sampleNwp;
  Object? nextNwpError;

  @override
  Future<List<NwpPoint>> fetchForecast(double lat, double lon) async {
    if (nextNwpError != null) throw nextNwpError!;
    return nextNwp;
  }
}

void main() {
  late FakeWeatherApi fakeWeatherApi;
  late FakeAlertsApi fakeAlertsApi;
  late FakeNwpApi fakeNwpApi;
  late ProviderContainer container;

  // Declared here rather than in test/support so these tests stay
  // self-contained: they deliberately exercise the no-fix path.

  setUp(() {
    fakeWeatherApi = FakeWeatherApi()..nextWeather = _sampleWeather;
    fakeAlertsApi = FakeAlertsApi()..nextAlerts = [_nearbyAlert, _farAlert, _noCoordsAlert];
    fakeNwpApi = FakeNwpApi();
    container = ProviderContainer(
      overrides: [
        weatherApiProvider.overrideWithValue(fakeWeatherApi),
        alertsApiProvider.overrideWithValue(fakeAlertsApi),
        nwpApiProvider.overrideWithValue(fakeNwpApi),
        // loadInitial() now asks the device for its position first. These
        // tests are about the fetch-and-filter logic, not location, so
        // the device reports no fix and the controller falls back to its
        // default city — which is the coordinate every assertion below
        // was already written against.
        deviceLocationProvider.overrideWithValue(
          const _NoDeviceFix(),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('starts in HomeLoading', () {
    expect(container.read(homeControllerProvider), isA<HomeLoading>());
  });

  test('loadInitial fetches for New Delhi and populates HomeLoaded', () async {
    await container.read(homeControllerProvider.notifier).loadInitial();

    final state = container.read(homeControllerProvider);
    expect(state, isA<HomeLoaded>());
    final loaded = state as HomeLoaded;
    expect(loaded.location.displayName, contains('Delhi'));
    expect(loaded.weather.temperatureC, 32.0);
    expect(loaded.forecast, hasLength(1));
    expect(fakeWeatherApi.fetchCurrentCalls.single, [28.6139, 77.2090]);
  });

  test('loadInitial filters alerts to within 100km, excluding the far one and the one with no coordinates', () async {
    await container.read(homeControllerProvider.notifier).loadInitial();

    final loaded = container.read(homeControllerProvider) as HomeLoaded;
    expect(loaded.nearbyAlerts, hasLength(1));
    expect(loaded.nearbyAlerts.single.id, 1);
  });

  test('changeLocation re-fetches for the new coordinates', () async {
    await container.read(homeControllerProvider.notifier).loadInitial();

    const mumbai = GeocodeResult(
      displayName: 'Mumbai, India',
      latitude: 19.0760,
      longitude: 72.8777,
      country: 'India',
      state: 'Maharashtra',
    );
    await container.read(homeControllerProvider.notifier).changeLocation(mumbai);

    final loaded = container.read(homeControllerProvider) as HomeLoaded;
    expect(loaded.location.displayName, 'Mumbai, India');
    expect(fakeWeatherApi.fetchCurrentCalls.last, [19.0760, 72.8777]);
  });

  test('a fetch failure surfaces HomeError with the real AppError', () async {
    fakeWeatherApi.nextWeatherError = const NetworkTimeoutError();

    await container.read(homeControllerProvider.notifier).loadInitial();

    final state = container.read(homeControllerProvider);
    expect(state, isA<HomeError>());
    expect((state as HomeError).error, isA<NetworkTimeoutError>());
  });

  test('retry re-issues the fetch and can recover from a prior failure', () async {
    fakeWeatherApi.nextWeatherError = const NetworkTimeoutError();
    await container.read(homeControllerProvider.notifier).loadInitial();
    expect(container.read(homeControllerProvider), isA<HomeError>());

    fakeWeatherApi.nextWeatherError = null;
    await container.read(homeControllerProvider.notifier).retry();

    expect(container.read(homeControllerProvider), isA<HomeLoaded>());
  });

  group('NWP exemption', () {
    // Mirrors the air-quality exemption already covered above: NWP is a
    // different data source than weather/forecast/alerts, and its outage
    // must not blank an otherwise-working weather screen.

    test('loadInitial populates nwp when the call succeeds', () async {
      await container.read(homeControllerProvider.notifier).loadInitial();

      final loaded = container.read(homeControllerProvider) as HomeLoaded;
      expect(loaded.nwp, _sampleNwp);
    });

    test('a failing NWP call does NOT fail the Home screen', () async {
      fakeNwpApi.nextNwpError = const NetworkTimeoutError();

      await container.read(homeControllerProvider.notifier).loadInitial();

      final state = container.read(homeControllerProvider);
      expect(state, isA<HomeLoaded>());
      final loaded = state as HomeLoaded;
      // The screen still has real weather — NWP just leaves its own field
      // null rather than taking down the whole load.
      expect(loaded.weather.temperatureC, 32.0);
      expect(loaded.nwp, isNull);
    });

    test('an empty NWP array is not an error — ingestion has not run yet',
        () async {
      fakeNwpApi.nextNwp = const [];

      await container.read(homeControllerProvider.notifier).loadInitial();

      final loaded = container.read(homeControllerProvider) as HomeLoaded;
      expect(loaded.nwp, isEmpty);
    });
  });
}
