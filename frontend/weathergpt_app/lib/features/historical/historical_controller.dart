import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/geocoding_api.dart';
import '../../data/historical_api.dart';

sealed class HistoricalUiState {
  const HistoricalUiState();
}

class HistoricalLoading extends HistoricalUiState {
  const HistoricalLoading();
}

/// The coverage list itself came back empty — the seed table is truncated
/// by the backend's own test suite and re-seeding is expensive, so this is
/// a real, expected state ("no historical data loaded"), not an error.
class HistoricalCoverageEmpty extends HistoricalUiState {
  const HistoricalCoverageEmpty();
}

/// `location`/`date` came from the coverage response, yet the lookup still
/// 404s. Coverage should make this unreachable in practice, but the lookup
/// is a separate request against a live table, so it is handled distinctly
/// from [HistoricalError] rather than assumed impossible.
class HistoricalNotFound extends HistoricalUiState {
  final List<HistoricalCoverage> coverage;
  final HistoricalCoverage location;
  final String date;

  const HistoricalNotFound({
    required this.coverage,
    required this.location,
    required this.date,
  });
}

class HistoricalError extends HistoricalUiState {
  final AppError error;
  const HistoricalError(this.error);
}

class HistoricalLoaded extends HistoricalUiState {
  final List<HistoricalCoverage> coverage;
  final HistoricalCoverage location;
  final String date;
  final HistoricalReading reading;

  /// The other date at [location] sharing [date]'s month-and-day, if one
  /// exists (e.g. 2024-07-15 and 2023-07-15 are both 15 July). Null when no
  /// such pair exists — the screen must then show the single reading with
  /// no comparison, never one built from unrelated dates.
  final String? comparisonDate;
  final HistoricalReading? comparisonReading;

  const HistoricalLoaded({
    required this.coverage,
    required this.location,
    required this.date,
    required this.reading,
    this.comparisonDate,
    this.comparisonReading,
  });

  bool get hasComparison => comparisonReading != null;
}

final historicalApiProvider =
    Provider<HistoricalApi>((ref) => HistoricalApi(buildApiClient()));

final historicalControllerProvider =
    NotifierProvider<HistoricalController, HistoricalUiState>(
        HistoricalController.new);

/// Loads ERA5 reanalysis coverage, then a chosen location/date within it.
///
/// Mirrors `AviationController`'s shape: a `Notifier` around a sealed UI
/// state, keeping the last-requested arguments as fields so retry does not
/// need them re-supplied. Unlike Aviation, there is no live "nearest"
/// concept here — [load] only PREFERS Home's current location among
/// whatever the coverage response actually offers, and falls back to
/// coverage's first entry when Home's location is not covered.
class HistoricalController extends Notifier<HistoricalUiState> {
  List<HistoricalCoverage>? _coverage;
  HistoricalCoverage? _location;
  String? _date;

  @override
  HistoricalUiState build() => const HistoricalLoading();

  /// Loads the full coverage list, then defaults to the entry matching
  /// [preferredLocation] (Home's current location) when the coverage
  /// contains it, else the first entry the backend returns. Safe to call
  /// again — e.g. pull-to-refresh — since it always refetches coverage
  /// rather than trying to detect a no-op, matching `AviationController`.
  Future<void> load({GeocodeResult? preferredLocation}) async {
    state = const HistoricalLoading();
    try {
      final coverage = await ref.read(historicalApiProvider).fetchAvailable();
      _coverage = coverage;
      if (coverage.isEmpty) {
        _location = null;
        _date = null;
        state = const HistoricalCoverageEmpty();
        return;
      }
      final location = _pickLocation(preferredLocation, coverage);
      _location = location;
      _date = location.dates.first;
      await _loadReading();
    } on AppError catch (e) {
      state = HistoricalError(e);
    }
  }

  /// Switches to a different covered location, defaulting to its most
  /// recent date.
  Future<void> selectLocation(HistoricalCoverage location) {
    _location = location;
    _date = location.dates.first;
    return _loadReading();
  }

  /// Switches to a different date at the currently selected location. The
  /// date must come from that location's own coverage list — the screen
  /// only ever offers dates from there, so this does not re-validate.
  Future<void> selectDate(String date) {
    _date = date;
    return _loadReading();
  }

  /// Re-issues whatever was last requested. Falls back to a full reload
  /// when coverage was never loaded (e.g. retrying after the initial
  /// coverage fetch itself failed).
  Future<void> retry() {
    if (_coverage == null) return load();
    return _loadReading();
  }

  Future<void> _loadReading() async {
    final coverage = _coverage;
    final location = _location;
    final date = _date;
    if (coverage == null || location == null || date == null) return;

    state = const HistoricalLoading();
    final api = ref.read(historicalApiProvider);

    try {
      final reading = await api.fetch(location.locationName, date);
      if (reading == null) {
        state = HistoricalNotFound(
          coverage: coverage,
          location: location,
          date: date,
        );
        return;
      }

      final comparisonDate = _sameMonthDayPartner(location, date);
      HistoricalReading? comparisonReading;
      if (comparisonDate != null) {
        // The comparison is an enhancement, not the point of the request —
        // if fetching the partner date fails for any reason, the primary
        // reading still shows, just without a comparison.
        try {
          comparisonReading =
              await api.fetch(location.locationName, comparisonDate);
        } catch (_) {
          comparisonReading = null;
        }
      }

      state = HistoricalLoaded(
        coverage: coverage,
        location: location,
        date: date,
        reading: reading,
        comparisonDate: comparisonReading == null ? null : comparisonDate,
        comparisonReading: comparisonReading,
      );
    } on AppError catch (e) {
      state = HistoricalError(e);
    }
  }

  HistoricalCoverage _pickLocation(
    GeocodeResult? preferred,
    List<HistoricalCoverage> coverage,
  ) {
    if (preferred != null) {
      final name = preferred.displayName.toLowerCase();
      for (final entry in coverage) {
        if (name.contains(entry.locationName.toLowerCase())) return entry;
      }
    }
    return coverage.first;
  }

  /// The other date at [location] with the same "MM-DD" suffix as [date],
  /// if any — e.g. 2024-07-15 and 2023-07-15 are both 15 July. Dates are
  /// ISO-8601 (`YYYY-MM-DD`), so the suffix is a plain substring; no date
  /// parsing is needed. Returns null rather than picking an unrelated date
  /// when no genuine same-day pair exists.
  String? _sameMonthDayPartner(HistoricalCoverage location, String date) {
    if (date.length != 10) return null;
    final monthDay = date.substring(5);
    for (final candidate in location.dates) {
      if (candidate == date) continue;
      if (candidate.length == 10 && candidate.substring(5) == monthDay) {
        return candidate;
      }
    }
    return null;
  }
}
