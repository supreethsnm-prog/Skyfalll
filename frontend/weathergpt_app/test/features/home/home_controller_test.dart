import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

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

void main() {
  late FakeWeatherApi fakeWeatherApi;
  late FakeAlertsApi fakeAlertsApi;
  late ProviderContainer container;

  setUp(() {
    fakeWeatherApi = FakeWeatherApi()..nextWeather = _sampleWeather;
    fakeAlertsApi = FakeAlertsApi()..nextAlerts = [_nearbyAlert, _farAlert, _noCoordsAlert];
    container = ProviderContainer(
      overrides: [
        weatherApiProvider.overrideWithValue(fakeWeatherApi),
        alertsApiProvider.overrideWithValue(fakeAlertsApi),
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
}
