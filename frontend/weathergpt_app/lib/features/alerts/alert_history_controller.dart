import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo.dart';
import '../../core/network/app_error.dart';
import '../../data/alerts_api.dart';
import '../home/home_controller.dart' show alertsApiProvider;

/// How far back "alerts from the past week" looks, and how far from the
/// current location an alert counts as relevant — matches
/// `HomeController`'s own nearby-alert radius, so this screen agrees with
/// what Home considers "near here".
const alertHistoryWindowDays = 7;
const alertHistoryRadiusKm = 100.0;

sealed class AlertHistoryUiState {
  const AlertHistoryUiState();
}

class AlertHistoryLoading extends AlertHistoryUiState {
  const AlertHistoryLoading();
}

/// `alerts` is already filtered to [alertHistoryRadiusKm] of
/// [locationName] and to the last [alertHistoryWindowDays] days, newest
/// first. An empty list is a real, valid outcome — quiet is the honest
/// answer when nothing happened nearby this week.
class AlertHistoryLoaded extends AlertHistoryUiState {
  final String locationName;
  final List<AlertSummary> alerts;
  const AlertHistoryLoaded({required this.locationName, required this.alerts});
}

class AlertHistoryError extends AlertHistoryUiState {
  final AppError error;
  const AlertHistoryError(this.error);
}

final alertHistoryControllerProvider =
    NotifierProvider<AlertHistoryController, AlertHistoryUiState>(
  AlertHistoryController.new,
);

/// A week's worth of alert history near a given location.
///
/// Takes the location as a parameter rather than reading Home's state
/// itself — mirrors `AdvisoryController`'s shape. The SCREEN owns
/// resolving "where is Home currently showing" (including the case where
/// Home hasn't loaded yet) and calls [load] once it knows.
class AlertHistoryController extends Notifier<AlertHistoryUiState> {
  @override
  AlertHistoryUiState build() => const AlertHistoryLoading();

  double? _lat;
  double? _lon;
  String? _name;

  Future<void> load(double latitude, double longitude, String locationName) {
    _lat = latitude;
    _lon = longitude;
    _name = locationName;
    return _fetch();
  }

  Future<void> retry() => _fetch();

  Future<void> _fetch() async {
    final lat = _lat;
    final lon = _lon;
    final name = _name;
    if (lat == null || lon == null || name == null) return;

    state = const AlertHistoryLoading();
    try {
      final all = await ref.read(alertsApiProvider).fetchAlerts();
      final cutoff = DateTime.now().toUtc().subtract(
            const Duration(days: alertHistoryWindowDays),
          );

      final nearby = <AlertSummary>[];
      for (final alert in all) {
        if (alert.latitude == null || alert.longitude == null) continue;
        if (alert.fetchedAt == null) continue;
        final fetchedAt = DateTime.tryParse(alert.fetchedAt!);
        if (fetchedAt == null || fetchedAt.isBefore(cutoff)) continue;
        final distance = haversineKm(lat, lon, alert.latitude!, alert.longitude!);
        if (distance <= alertHistoryRadiusKm) nearby.add(alert);
      }

      nearby.sort((a, b) => b.fetchedAt!.compareTo(a.fetchedAt!));
      state = AlertHistoryLoaded(locationName: name, alerts: nearby);
    } on AppError catch (e) {
      state = AlertHistoryError(e);
    }
  }
}
