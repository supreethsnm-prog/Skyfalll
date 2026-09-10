import 'dart:async';

import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/data/advisory_api.dart';
import 'package:weathergpt_app/data/air_quality_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/alerts_socket.dart';
import 'package:weathergpt_app/data/nwp_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/advisory/advisory_controller.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';

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

class FakeAirQualityApi implements AirQualityApi {
  @override
  Future<AirQuality> fetchCurrent(double lat, double lon) async {
    return const AirQuality(
      observedAt: '2026-09-09T14:00',
      usAqi: 156,
      pm25: 64.8,
      pm10: 118.2,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Stands in for `NwpApi`. Returns the single sample point from the
/// verified backend contract (`.superpowers/sdd/nwp-brief.md`) — a
/// realistic, common shape, not a placeholder — since `HomeController`
/// now fetches NWP alongside weather/forecast/alerts on every load.
/// Without this override, an unmocked `nwpApiProvider` builds a real Dio
/// against AppEnv's unreachable default host, and Home's exemption for a
/// failed NWP call (see `HomeController._load`) means the load succeeds
/// anyway — but only after sitting on a doomed socket for the full
/// connect timeout.
class FakeNwpApi implements NwpApi {
  @override
  Future<List<NwpPoint>> fetchForecast(double lat, double lon) async {
    return const [
      NwpPoint(
        runDate: '20260909',
        runHour: '18',
        forecastHour: 0,
        validTime: '2026-09-09T18:00:00Z',
        temp2mC: 32.09,
        relativeHumidity2mPct: 40.9,
        windSpeed10mKmh: 5.8,
        windDirection10mDeg: 233.67,
        windGustKmh: 9.42,
        precipRateMmh: 0.0,
        capeJPerKg: 0.0,
        cinJPerKg: -0.29,
        cloudCoverPct: 0.0,
        mslpHpa: 1005.99,
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

/// Stands in for `AdvisoryApi`, so any test that mounts `AdvisoryScreen`
/// (or a route tree that could reach it) does not make a live HTTP call.
/// Both responses default to "everything normal, nothing to report" —
/// LOW risk and no advisory text — which is itself a realistic, common
/// outcome for this endpoint, not a placeholder to gloss over.
class FakeAdvisoryApi implements AdvisoryApi {
  @override
  Future<AgricultureAdvisory> fetchAgriculture(
    double lat,
    double lon, {
    String? crop,
    int days = 5,
  }) async {
    return AgricultureAdvisory(
      latitude: lat,
      longitude: lon,
      crop: crop,
      generatedAt: '2026-09-09T14:00',
      advisories: const [],
      activeAlerts: const [],
      forecastBasis: const [],
    );
  }

  @override
  Future<UrbanAdvisory> fetchUrban(double lat, double lon, {int days = 5}) async {
    return UrbanAdvisory(
      latitude: lat,
      longitude: lon,
      generatedAt: '2026-09-09T14:00',
      riskSummary: const UrbanRiskSummary(
        waterloggingRisk: 'LOW',
        heatRisk: 'LOW',
        windRisk: 'LOW',
      ),
      advisories: const [],
      activeAlerts: const [],
      forecastBasis: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Device location that reports no fix, so tests exercise the default-city
/// path without touching the geolocator plugin — which is not available in
/// a widget test and throws MissingPluginException if reached.
class FakeDeviceLocation implements DeviceLocation {
  const FakeDeviceLocation([this.result = const LocationFixed(28.6139, 77.2090)]);

  final LocationResult result;

  @override
  Future<LocationResult> current() async => result;
}

/// Names any coordinate as the default city, so Home's hero renders a
/// stable place name without a network call.
class FakeGeocodingApi implements GeocodingApi {
  const FakeGeocodingApi();

  @override
  Future<GeocodeResult?> reverse(double lat, double lon) async =>
      const GeocodeResult(
        displayName: 'New Delhi, India',
        latitude: 28.6139,
        longitude: 77.2090,
        country: 'India',
        state: 'Delhi',
      );

  @override
  Future<GeocodeResult?> search(String query) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A socket that never emits, so tests do not open a real connection.
/// `HomeScreen` subscribes on its first frame, and without this every
/// widget test would try to reach ws://127.0.0.1:8000.
class FakeAlertsSocket implements AlertsSocket {
  final controller = StreamController<List<AlertSummary>>.broadcast();

  @override
  Stream<List<AlertSummary>> get newAlerts => controller.stream;

  @override
  void dispose() => controller.close();
}


/// In-memory saved places, so tests do not need the shared_preferences
/// plugin — which has no implementation in a widget test and throws
/// MissingPluginException the moment Home's chrome reads the provider.
class FakeSavedPlacesStore implements SavedPlacesStore {
  FakeSavedPlacesStore([this.places = const []]);

  List<GeocodeResult> places;

  @override
  Future<List<GeocodeResult>> load() async => places;

  @override
  Future<void> save(List<GeocodeResult> next) async => places = next;
}

/// In-memory chat history, so the drawer's Recents list does not reach
/// for shared_preferences in a widget test.
class FakeConversationStore implements ConversationStore {
  FakeConversationStore([this.conversations = const []]);

  List<Conversation> conversations;

  @override
  Future<List<Conversation>> load() async => conversations;

  @override
  Future<void> save(List<Conversation> next) async => conversations = next;
}

/// Drop-in overrides for any `ProviderScope` mounting `HomeScreen`.
///
/// The return type is inferred rather than written out: Riverpod 3 does
/// not export a public name for it. The fakes are stateless, so one
/// shared list is safe across tests.
final fakeApiOverrides = [
  weatherApiProvider.overrideWithValue(FakeWeatherApi()),
  alertsApiProvider.overrideWithValue(FakeAlertsApi()),
  airQualityApiProvider.overrideWithValue(FakeAirQualityApi()),
  nwpApiProvider.overrideWithValue(FakeNwpApi()),
  advisoryApiProvider.overrideWithValue(FakeAdvisoryApi()),
  deviceLocationProvider.overrideWithValue(const FakeDeviceLocation()),
  geocodingApiProvider.overrideWithValue(const FakeGeocodingApi()),
  alertsSocketProvider.overrideWithValue(FakeAlertsSocket()),
  savedPlacesStoreProvider.overrideWithValue(FakeSavedPlacesStore()),
  conversationStoreProvider.overrideWithValue(FakeConversationStore()),
];
