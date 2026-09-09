import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/geo.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/air_quality_api.dart';
import '../../data/alerts_api.dart';
import '../../data/geocoding_api.dart';
import '../../data/weather_api.dart';

/// New Delhi — the fixed default starting location for this phase.
/// No GPS/device-location integration exists yet (deliberate scope
/// cut, see spec §6c); the user switches location via search.
const _defaultLocation = GeocodeResult(
  displayName: 'New Delhi, India',
  latitude: 28.6139,
  longitude: 77.2090,
  country: 'India',
  state: 'Delhi',
);

const _alertRadiusKm = 100.0;

sealed class HomeUiState {
  const HomeUiState();
}

class HomeLoading extends HomeUiState {
  const HomeLoading();
}

class HomeLoaded extends HomeUiState {
  final GeocodeResult location;
  final CurrentWeather weather;
  final List<ForecastDay> forecast;
  final List<AlertSummary> nearbyAlerts;

  /// Null when the air-quality call failed. Deliberately optional: unlike
  /// the other three fetches, a missing AQI reading does NOT fail the
  /// screen — see the note in [HomeController._load].
  final AirQuality? airQuality;

  const HomeLoaded({
    required this.location,
    required this.weather,
    required this.forecast,
    required this.nearbyAlerts,
    this.airQuality,
  });
}

class HomeError extends HomeUiState {
  final AppError error;

  const HomeError(this.error);
}

final weatherApiProvider = Provider<WeatherApi>((ref) => WeatherApi(buildApiClient()));
final alertsApiProvider = Provider<AlertsApi>((ref) => AlertsApi(buildApiClient()));
final geocodingApiProvider = Provider<GeocodingApi>((ref) => GeocodingApi(buildApiClient()));
final airQualityApiProvider =
    Provider<AirQualityApi>((ref) => AirQualityApi(buildApiClient()));

final homeControllerProvider =
    NotifierProvider<HomeController, HomeUiState>(HomeController.new);

/// Fetches weather, forecast, and alerts together for one location.
/// On ANY of the three failing, the whole state becomes [HomeError] —
/// a deliberate simplification for this phase (no partial-degrade
/// granularity, e.g. showing weather while alerts failed) rather than
/// an oversight.
class HomeController extends Notifier<HomeUiState> {
  GeocodeResult _location = _defaultLocation;

  @override
  HomeUiState build() => const HomeLoading();

  Future<void> loadInitial() => _load(_defaultLocation);

  Future<void> changeLocation(GeocodeResult location) => _load(location);

  Future<void> retry() => _load(_location);

  Future<void> _load(GeocodeResult location) async {
    state = const HomeLoading();
    final weatherApi = ref.read(weatherApiProvider);
    final alertsApi = ref.read(alertsApiProvider);
    final airQualityApi = ref.read(airQualityApiProvider);

    // Air quality is fetched alongside the others but is deliberately
    // EXEMPT from this controller's otherwise all-or-nothing rule: it
    // comes from a different upstream host, so its outage must not blank
    // a weather screen that is otherwise fine. A failure here leaves
    // airQuality null and the AQI pill simply does not render.
    final airQualityFuture = airQualityApi
        .fetchCurrent(location.latitude, location.longitude)
        .then<AirQuality?>((value) => value)
        .catchError((_) => null);

    try {
      final results = await Future.wait([
        weatherApi.fetchCurrent(location.latitude, location.longitude),
        weatherApi.fetchForecast(location.latitude, location.longitude),
        alertsApi.fetchAlerts(),
      ]);
      final weather = results[0] as CurrentWeather;
      final forecast = results[1] as List<ForecastDay>;
      final allAlerts = results[2] as List<AlertSummary>;

      final nearbyAlerts = allAlerts.where((alert) {
        if (alert.latitude == null || alert.longitude == null) return false;
        final distance = haversineKm(
          location.latitude,
          location.longitude,
          alert.latitude!,
          alert.longitude!,
        );
        return distance <= _alertRadiusKm;
      }).toList();

      _location = location;
      state = HomeLoaded(
        location: location,
        weather: weather,
        forecast: forecast,
        nearbyAlerts: nearbyAlerts,
        airQuality: await airQualityFuture,
      );
    } on AppError catch (e) {
      _location = location;
      state = HomeError(e);
    }
  }
}
