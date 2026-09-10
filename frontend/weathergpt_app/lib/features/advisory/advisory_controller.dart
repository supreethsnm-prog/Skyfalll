import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/advisory_api.dart';
import '../../data/geocoding_api.dart';

sealed class AdvisoryUiState {
  const AdvisoryUiState();
}

class AdvisoryLoading extends AdvisoryUiState {
  const AdvisoryLoading();
}

class AdvisoryLoaded extends AdvisoryUiState {
  final GeocodeResult location;
  final UrbanAdvisory urban;
  final AgricultureAdvisory agriculture;

  /// The crop this load was fetched for, mirrored from the request rather
  /// than re-derived from `agriculture.crop` so the screen can compare it
  /// against the currently-selected chip even while a refetch for a
  /// different crop is still in flight.
  final String? crop;

  const AdvisoryLoaded({
    required this.location,
    required this.urban,
    required this.agriculture,
    required this.crop,
  });
}

class AdvisoryError extends AdvisoryUiState {
  final AppError error;
  const AdvisoryError(this.error);
}

final advisoryApiProvider =
    Provider<AdvisoryApi>((ref) => AdvisoryApi(buildApiClient()));

final advisoryControllerProvider =
    NotifierProvider<AdvisoryController, AdvisoryUiState>(
        AdvisoryController.new);

/// Fetches the urban and agriculture advisories together for one location.
///
/// Deliberately mirrors [HomeController]'s shape (build a `Notifier` around
/// a sealed UI state, keep the last-requested arguments as fields so a
/// retry/refetch does not need them re-supplied), but this screen never
/// picks its own location — it is always told one, read from
/// `homeControllerProvider` by the screen. Two screens disagreeing about
/// where the user is would be worse than making Advisories wait for Home.
class AdvisoryController extends Notifier<AdvisoryUiState> {
  GeocodeResult? _location;
  String? _crop;

  @override
  AdvisoryUiState build() => const AdvisoryLoading();

  /// Loads both advisories for [location]. Safe to call again for the same
  /// location (e.g. the screen re-checking after Home's location settles)
  /// — it always refetches rather than trying to detect a no-op, since a
  /// caller that already knows the location is unchanged should not call
  /// this in the first place.
  Future<void> load(GeocodeResult location, {String? crop}) {
    _location = location;
    _crop = crop;
    return _fetchAll();
  }

  Future<void> retry() => _fetchAll();

  /// Refetches only the agriculture advisory for a new crop filter.
  ///
  /// The urban risk tiles do not depend on crop, so keeping them exactly as
  /// they were while only the crop-specific list reloads avoids a jarring
  /// full-screen loading flash every time someone taps a different chip —
  /// unlike [load]/[retry], which legitimately need to replace everything.
  Future<void> changeCrop(String? crop) async {
    final location = _location;
    if (location == null) return;
    _crop = crop;

    final current = state;
    if (current is! AdvisoryLoaded) {
      // Nothing to keep in place yet — fall back to the full fetch.
      await _fetchAll();
      return;
    }

    try {
      final agriculture = await ref
          .read(advisoryApiProvider)
          .fetchAgriculture(location.latitude, location.longitude, crop: crop);
      state = AdvisoryLoaded(
        location: current.location,
        urban: current.urban,
        agriculture: agriculture,
        crop: crop,
      );
    } on AppError catch (e) {
      state = AdvisoryError(e);
    }
  }

  Future<void> _fetchAll() async {
    final location = _location;
    if (location == null) return;

    state = const AdvisoryLoading();
    final api = ref.read(advisoryApiProvider);

    try {
      final results = await Future.wait([
        api.fetchUrban(location.latitude, location.longitude),
        api.fetchAgriculture(location.latitude, location.longitude,
            crop: _crop),
      ]);
      state = AdvisoryLoaded(
        location: location,
        urban: results[0] as UrbanAdvisory,
        agriculture: results[1] as AgricultureAdvisory,
        crop: _crop,
      );
    } on AppError catch (e) {
      state = AdvisoryError(e);
    }
  }
}
