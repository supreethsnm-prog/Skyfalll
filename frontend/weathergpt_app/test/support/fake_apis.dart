import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

/// Offline stand-ins for the network layer.
///
/// `HomeScreen` calls `loadInitial()` on its first frame, so any test that
/// pumps the real app — router tests, boot tests — makes a live HTTP call
/// unless these are overridden. flutter_test blocks real sockets, so the
/// failure is a confusing HttpClient error rather than an obvious one.
/// Anything that mounts `HomeScreen` should use [fakeApiOverrides].

class FakeWeatherApi implements WeatherApi {
  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    return const CurrentWeather(
      temperatureC: 24.4,
      humidityPct: 78,
      weatherCode: 1,
      windSpeedKmh: 18.2,
      windDirectionDeg: 247,
      observedAt: '2026-09-09T14:00',
      timezone: 'Asia/Kolkata',
    );
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon,
      {int days = 5}) async {
    return const [
      ForecastDay(
        forecastDate: '2026-09-09',
        weatherCode: 1,
        tempMaxC: 31.2,
        tempMinC: 24.1,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeAlertsApi implements AlertsApi {
  @override
  Future<List<AlertSummary>> fetchAlerts() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Drop-in overrides for any `ProviderScope` mounting `HomeScreen`.
///
/// The return type is inferred rather than written out: Riverpod 3 does
/// not export a public name for it. The fakes are stateless, so one
/// shared list is safe across tests.
final fakeApiOverrides = [
  weatherApiProvider.overrideWithValue(FakeWeatherApi()),
  alertsApiProvider.overrideWithValue(FakeAlertsApi()),
];
