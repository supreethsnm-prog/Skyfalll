import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/marine_api.dart';

sealed class MarineUiState {
  const MarineUiState();
}

class MarineLoading extends MarineUiState {
  const MarineLoading();
}

/// `zones` can legitimately be empty — see `MarineApi.fetchPfzZones` — so
/// this one loaded state covers both "N zones" and "ingestion hasn't run
/// yet"; the screen, not the controller, decides how each renders.
class MarineLoaded extends MarineUiState {
  final List<PfzZone> zones;
  const MarineLoaded(this.zones);
}

class MarineError extends MarineUiState {
  final AppError error;
  const MarineError(this.error);
}

final marineApiProvider =
    Provider<MarineApi>((ref) => MarineApi(buildApiClient()));

final marineControllerProvider =
    NotifierProvider<MarineController, MarineUiState>(MarineController.new);

/// Fetches the live INCOIS PFZ advisories.
///
/// Unlike `AdvisoryController`/`AviationController`, this screen does not
/// wait on Home's location — `GET /marine/pfz-zones` returns every current
/// zone nationwide in one call, and the map fits itself to whatever comes
/// back. Otherwise mirrors their shape: a `Notifier` around a sealed UI
/// state, with `retry` re-running the same fetch.
class MarineController extends Notifier<MarineUiState> {
  @override
  MarineUiState build() => const MarineLoading();

  Future<void> load() => _fetch();

  Future<void> retry() => _fetch();

  Future<void> _fetch() async {
    state = const MarineLoading();
    try {
      final zones = await ref.read(marineApiProvider).fetchPfzZones();
      state = MarineLoaded(zones);
    } on AppError catch (e) {
      state = MarineError(e);
    }
  }
}
