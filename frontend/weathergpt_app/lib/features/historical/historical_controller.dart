import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/geocoding_api.dart';
import '../../data/historical_api.dart';

/// New Delhi — the fallback location used until a location is chosen or
/// Home's current location resolves. Mirrors `HomeController`'s own
/// `_defaultLocation` fallback.
const _defaultLocation = GeocodeResult(
  displayName: 'New Delhi, India',
  latitude: 28.6139,
  longitude: 77.2090,
  country: 'India',
  state: 'Delhi',
);

/// Archive coverage lags the live feed by a few days — see
/// `historicalDateBounds` below — so the default date opens on a day that
/// is guaranteed to already have data rather than the most recent possible
/// one.
const _defaultDateLagDays = 10;

sealed class HistoricalUiState {
  const HistoricalUiState();
}

class HistoricalLoading extends HistoricalUiState {
  const HistoricalLoading();
}

/// The archive has no reading for this exact (location, date) — e.g. a
/// date just outside real coverage. An expected outcome given free-form
/// date entry, not an error.
class HistoricalNotFound extends HistoricalUiState {
  final GeocodeResult location;
  final String date;

  const HistoricalNotFound({required this.location, required this.date});
}

class HistoricalError extends HistoricalUiState {
  final AppError error;
  const HistoricalError(this.error);
}

class HistoricalLoaded extends HistoricalUiState {
  final GeocodeResult location;
  final String date;
  final ArchiveReading reading;

  /// The same calendar date one year earlier, if the archive has it.
  final ArchiveReading? previousYearReading;

  const HistoricalLoaded({
    required this.location,
    required this.date,
    required this.reading,
    this.previousYearReading,
  });

  bool get hasComparison => previousYearReading != null;
}

final historicalApiProvider =
    Provider<HistoricalApi>((ref) => HistoricalApi(buildApiClient()));

final historicalControllerProvider =
    NotifierProvider<HistoricalController, HistoricalUiState>(
        HistoricalController.new);

/// Any location on Earth, any date the Open-Meteo Archive covers.
///
/// Keeps the last-requested location/date as fields so a retry, or
/// changing just one of the two, does not need the other re-supplied.
/// Mirrors `AviationController`'s shape.
class HistoricalController extends Notifier<HistoricalUiState> {
  GeocodeResult? _location;
  String? _date;

  /// Once the user has explicitly picked a location, Home's location
  /// resolving (or re-resolving) must never silently override that choice.
  bool _userPickedLocation = false;

  @override
  HistoricalUiState build() => const HistoricalLoading();

  /// Loads the currently selected (or default) location/date. Safe to call
  /// repeatedly — e.g. pull-to-refresh, or Home's location resolving after
  /// this screen already opened — since it always re-fetches. Adopts
  /// [preferredLocation] (Home's current location) only until the user
  /// picks a location of their own.
  Future<void> load({GeocodeResult? preferredLocation}) async {
    if (!_userPickedLocation) {
      _location = preferredLocation ?? _defaultLocation;
    }
    _date ??= _defaultDate();
    await _fetch();
  }

  /// Switches to a different location (from the location search sheet),
  /// keeping the currently selected date.
  Future<void> selectLocation(GeocodeResult location) {
    _userPickedLocation = true;
    _location = location;
    _date ??= _defaultDate();
    return _fetch();
  }

  /// Switches to a different date (from the date picker), keeping the
  /// currently selected location.
  Future<void> selectDate(String date) {
    _date = date;
    return _fetch();
  }

  /// Re-issues whatever was last requested.
  Future<void> retry() => _fetch();

  Future<void> _fetch() async {
    final location = _location;
    final date = _date;
    if (location == null || date == null) return;

    state = const HistoricalLoading();
    try {
      final result = await ref.read(historicalApiProvider).fetchArchive(
            latitude: location.latitude,
            longitude: location.longitude,
            date: date,
            name: location.displayName,
          );
      if (result == null) {
        state = HistoricalNotFound(location: location, date: date);
        return;
      }
      state = HistoricalLoaded(
        location: location,
        date: date,
        reading: result.reading,
        previousYearReading: result.previousYearReading,
      );
    } on AppError catch (e) {
      state = HistoricalError(e);
    }
  }

  String _defaultDate() {
    final d = DateTime.now().toUtc().subtract(
          const Duration(days: _defaultDateLagDays),
        );
    return _isoDate(d);
  }
}

/// `YYYY-MM-DD` for a [DateTime], with no time-of-day component — matches
/// the backend's date query parameter shape.
String _isoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// `showDatePicker` bounds for the Open-Meteo Archive: it covers 1940
/// onward, and lags the live feed by roughly 5 days, so a conservative
/// 6-day buffer keeps every offered date from 404ing.
({DateTime first, DateTime last}) historicalDateBounds() {
  final now = DateTime.now().toUtc();
  final last = DateTime(now.year, now.month, now.day).subtract(
    const Duration(days: 6),
  );
  return (first: DateTime(1940, 1, 1), last: last);
}

/// Exposed for the screen's date picker, which needs the same `YYYY-MM-DD`
/// shape [HistoricalController] sends to the backend.
String isoDateString(DateTime d) => _isoDate(d);
