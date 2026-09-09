import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/geo.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../core/location/device_location.dart';
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

  /// Non-null when Home is showing the DEFAULT city because the device's
  /// own location could not be used. Lets the UI say so and offer the
  /// right remedy, instead of silently presenting Delhi as "here".
  final LocationFailure? locationFailure;

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
    this.locationFailure,
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

final deviceLocationProvider =
    Provider<DeviceLocation>((ref) => const GeolocatorDeviceLocation());

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

  /// Why the screen is not showing the device's own location, or null
  /// when it is. Surfaced so Home can offer the right remedy — a retry
  /// for a denial, a settings trip for a permanent one.
  LocationFailure? _locationFailure;

  Future<void> loadInitial() => useCurrentLocation();

  Future<void> changeLocation(GeocodeResult location) {
    // An explicit choice wins: stop reporting a location failure the user
    // has already worked around by picking a place.
    _locationFailure = null;
    return _load(location);
  }

  Future<void> retry() => _load(_location);

  /// Resolves the device's position and loads weather for it, falling
  /// back to the default city when there is no fix.
  ///
  /// A denied permission is NOT an error state: the screen still shows
  /// real weather for the default city, with a note offering to use the
  /// device's location. Blocking the whole app on a permission the user
  /// declined would be worse than showing Delhi.
  Future<void> useCurrentLocation() async {
    state = const HomeLoading();

    final result = await ref.read(deviceLocationProvider).current();

    switch (result) {
      case LocationFixed(:final latitude, :final longitude):
        _locationFailure = null;
        // Name the coordinate so the hero reads "Pune, Maharashtra"
        // rather than a lat/lon pair. A naming failure is cosmetic, so it
        // degrades to a generic label rather than blocking the load.
        GeocodeResult? named;
        try {
          named = await ref
              .read(geocodingApiProvider)
              .reverse(latitude, longitude);
        } catch (_) {
          named = null;
        }
        await _load(
          named ??
              GeocodeResult(
                displayName: 'Current location',
                latitude: latitude,
                longitude: longitude,
                country: null,
                state: null,
              ),
        );
      case LocationUnavailable(:final reason):
        _locationFailure = reason;
        await _load(_defaultLocation);
    }
  }

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
        locationFailure: _locationFailure,
      );
    } on AppError catch (e) {
      _location = location;
      state = HomeError(e);
    }
  }
}
