import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/geo.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../core/location/device_location.dart';
import '../../data/air_quality_api.dart';
import '../../data/alerts_socket.dart';
import '../../data/alerts_api.dart';
import '../../data/geocoding_api.dart';
import '../../data/nwp_api.dart';
import '../../data/weather_api.dart';

/// New Delhi — the FALLBACK location, used when the device's own
/// position is unavailable (permission declined, location services off,
/// no fix). Home opens on the device location when it can; see
/// [HomeController.useCurrentLocation].
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

  /// Null when the NWP (NOAA GFS numerical weather prediction) call failed,
  /// OR when it succeeded with an empty array — `/nwp` reads from a table
  /// filled by scheduled ingestion, and an empty result is that ingestion's
  /// honest "nothing yet", not an error. Deliberately optional for the same
  /// reason [airQuality] is: a different upstream source, whose absence
  /// must not fail an otherwise-working weather screen — see the note in
  /// [HomeController._load].
  final List<NwpPoint>? nwp;

  const HomeLoaded({
    required this.location,
    required this.weather,
    required this.forecast,
    required this.nearbyAlerts,
    this.airQuality,
    this.nwp,
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
final nwpApiProvider = Provider<NwpApi>((ref) => NwpApi(buildApiClient()));

/// Live alert push. Kept alive for the app's lifetime rather than per
/// screen, so the connection survives navigation, and disposed with the
/// container so tests and hot restarts do not leak sockets.
final alertsSocketProvider = Provider<AlertsSocket>((ref) {
  final socket = WebSocketAlertsSocket();
  ref.onDispose(socket.dispose);
  return socket;
});

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

  /// Current or fallback location.
  GeocodeResult get currentLocation => _location;

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

  /// Merges alerts pushed over the socket into the current screen.
  ///
  /// Applies the SAME radius filter as a fetched load — a warning for
  /// Kerala must not appear on a Delhi screen just because it arrived
  /// live. Returns the alerts that were actually near enough to add, so
  /// the UI can announce exactly what it showed and stay silent when a
  /// batch was all far away.
  List<AlertSummary> mergeLiveAlerts(List<AlertSummary> incoming) {
    final current = state;
    if (current is! HomeLoaded) return const [];

    final existingIds = current.nearbyAlerts.map((a) => a.id).toSet();

    final relevant = incoming.where((alert) {
      if (existingIds.contains(alert.id)) return false;
      if (alert.latitude == null || alert.longitude == null) return false;
      final distance = haversineKm(
        current.location.latitude,
        current.location.longitude,
        alert.latitude!,
        alert.longitude!,
      );
      return distance <= _alertRadiusKm;
    }).toList();

    if (relevant.isEmpty) return const [];

    state = HomeLoaded(
      location: current.location,
      weather: current.weather,
      forecast: current.forecast,
      // Newest first: a warning that just arrived is the one to read.
      nearbyAlerts: [...relevant, ...current.nearbyAlerts],
      airQuality: current.airQuality,
      nwp: current.nwp,
      locationFailure: current.locationFailure,
    );

    return relevant;
  }

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
    final nwpApi = ref.read(nwpApiProvider);

    // Air quality is fetched alongside the others but is deliberately
    // EXEMPT from this controller's otherwise all-or-nothing rule: it
    // comes from a different upstream host, so its outage must not blank
    // a weather screen that is otherwise fine. A failure here leaves
    // airQuality null and the AQI pill simply does not render.
    final airQualityFuture = airQualityApi
        .fetchCurrent(location.latitude, location.longitude)
        .then<AirQuality?>((value) => value)
        .catchError((_) => null);

    // NWP (NOAA GFS numerical weather prediction) gets the SAME exemption
    // as air quality above, for the same reason: it is a different data
    // source than the core weather/forecast/alerts trio, so its outage
    // must not blank an otherwise-working screen. A failure here leaves
    // nwp null; the severe-weather panel treats that identically to a
    // successful-but-empty `/nwp` response (ingestion has not run yet) and
    // simply does not render.
    final nwpFuture = nwpApi
        .fetchForecast(location.latitude, location.longitude)
        .then<List<NwpPoint>?>((value) => value)
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
        nwp: await nwpFuture,
        locationFailure: _locationFailure,
      );
    } on AppError catch (e) {
      _location = location;
      state = HomeError(e);
    }
  }
}
