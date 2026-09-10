import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/geocoding_api.dart';
import '../../data/metar_api.dart';
import 'airports.dart';

sealed class AviationUiState {
  const AviationUiState();
}

class AviationLoading extends AviationUiState {
  const AviationLoading();
}

class AviationLoaded extends AviationUiState {
  final Airport airport;

  /// Distance from Home's current location to [airport], in km. Null only
  /// when a reading was somehow loaded before Home's location was ever
  /// known — should not happen given how the screen sequences loading, but
  /// a missing distance must never be rendered as 0km, which would claim
  /// the airport is local.
  final double? distanceKm;

  final MetarReading reading;

  const AviationLoaded({
    required this.airport,
    required this.distanceKm,
    required this.reading,
  });
}

/// The station has no current observation — the backend 404s that case,
/// and a station being temporarily silent is normal rather than an error.
/// Kept distinct from [AviationError] for the same reason
/// `GeocodingApi.search` returning null is not an error: the UI must say
/// "no reading right now", not "something went wrong".
class AviationNotFound extends AviationUiState {
  final Airport airport;
  final double? distanceKm;

  const AviationNotFound({required this.airport, required this.distanceKm});
}

class AviationError extends AviationUiState {
  final AppError error;
  const AviationError(this.error);
}

final metarApiProvider = Provider<MetarApi>((ref) => MetarApi(buildApiClient()));

final aviationControllerProvider =
    NotifierProvider<AviationController, AviationUiState>(
        AviationController.new);

/// Fetches the nearest (or a chosen) airport's METAR.
///
/// Mirrors `AdvisoryController`'s shape: a `Notifier` around a sealed UI
/// state, keeping the last-requested arguments as fields so retry/refetch
/// does not need them re-supplied. Like Advisories, this screen never
/// resolves its own location — it is always told Home's, via
/// [loadNearest] — but unlike Advisories, the user can then override the
/// derived airport with [selectAirport], independently of location.
class AviationController extends Notifier<AviationUiState> {
  GeocodeResult? _homeLocation;
  Airport? _airport;

  @override
  AviationUiState build() => const AviationLoading();

  /// Loads the airport nearest to [homeLocation]. Safe to call again for
  /// the same location (e.g. the screen re-checking after Home's location
  /// settles) — it always refetches rather than trying to detect a no-op,
  /// matching `AdvisoryController.load`.
  Future<void> loadNearest(GeocodeResult homeLocation) {
    _homeLocation = homeLocation;
    return _loadAirport(nearestAirport(homeLocation.latitude, homeLocation.longitude));
  }

  /// Loads a specific airport chosen from the picker, independent of
  /// distance — a METAR from 300km away is still useful, the screen just
  /// has to say so.
  Future<void> selectAirport(Airport airport) => _loadAirport(airport);

  Future<void> retry() {
    final airport = _airport;
    if (airport == null) return Future.value();
    return _loadAirport(airport);
  }

  Future<void> _loadAirport(Airport airport) async {
    _airport = airport;
    state = const AviationLoading();

    final home = _homeLocation;
    final distanceKm = home == null
        ? null
        : distanceToAirportKm(home.latitude, home.longitude, airport);

    try {
      final reading = await ref.read(metarApiProvider).fetch(airport.icao);
      state = reading == null
          ? AviationNotFound(airport: airport, distanceKm: distanceKm)
          : AviationLoaded(
              airport: airport, distanceKm: distanceKm, reading: reading);
    } on AppError catch (e) {
      state = AviationError(e);
    }
  }
}
