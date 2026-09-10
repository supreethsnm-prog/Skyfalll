import 'dart:async';

import 'package:weathergpt_app/core/location/device_location.dart';
import 'package:weathergpt_app/data/air_quality_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/alerts_socket.dart';
import 'package:weathergpt_app/data/weather_api.dart';
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

class FakeAlertsApi implements AlertsApi {
  @override
  Future<List<AlertSummary>> fetchAlerts() async => const [];

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
  deviceLocationProvider.overrideWithValue(const FakeDeviceLocation()),
  geocodingApiProvider.overrideWithValue(const FakeGeocodingApi()),
  alertsSocketProvider.overrideWithValue(FakeAlertsSocket()),
  savedPlacesStoreProvider.overrideWithValue(FakeSavedPlacesStore()),
  conversationStoreProvider.overrideWithValue(FakeConversationStore()),
];
