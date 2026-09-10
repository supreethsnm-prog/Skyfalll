import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/features/alerts/alert_history_controller.dart';
import 'package:weathergpt_app/features/home/home_controller.dart' show alertsApiProvider;

// Bengaluru — the location under test.
const _lat = 12.9716;
const _lon = 77.5946;

String _isoDaysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

/// Well within [alertHistoryRadiusKm] and [alertHistoryWindowDays] of
/// Bengaluru.
final _nearRecent = AlertSummary(
  id: 1,
  severity: 'Orange',
  eventType: 'Heavy Rain',
  areaDescription: 'Bengaluru Urban',
  latitude: _lat,
  longitude: _lon,
  fetchedAt: _isoDaysAgo(1),
);

/// Same place, but older than the window — must be excluded.
final _nearButOld = AlertSummary(
  id: 2,
  severity: 'Yellow',
  eventType: 'Thunderstorm',
  areaDescription: 'Bengaluru Urban',
  latitude: _lat,
  longitude: _lon,
  fetchedAt: _isoDaysAgo(10),
);

/// Recent, but roughly 1740 km away (New Delhi) — well outside the radius.
final _farButRecent = AlertSummary(
  id: 3,
  severity: 'Red',
  eventType: 'Flood',
  areaDescription: 'New Delhi',
  latitude: 28.6139,
  longitude: 77.2090,
  fetchedAt: _isoDaysAgo(1),
);

/// Near and recent, but no coordinates — relevance cannot be assessed,
/// so it must be excluded rather than assumed relevant.
final _noCoords = AlertSummary(
  id: 4,
  severity: 'Orange',
  eventType: 'Lightning',
  areaDescription: null,
  latitude: null,
  longitude: null,
  fetchedAt: _isoDaysAgo(1),
);

class _FakeAlertsApi implements AlertsApi {
  _FakeAlertsApi({this.alerts, this.error});

  final List<AlertSummary>? alerts;
  final AppError? error;

  @override
  Future<List<AlertSummary>> fetchAlerts() async {
    if (error != null) throw error!;
    return alerts ?? const [];
  }
}

ProviderContainer _containerWith(AlertsApi api) {
  return ProviderContainer(overrides: [alertsApiProvider.overrideWithValue(api)]);
}

void main() {
  test('starts in a loading state', () {
    final container = _containerWith(_FakeAlertsApi());
    addTearDown(container.dispose);

    expect(container.read(alertHistoryControllerProvider), isA<AlertHistoryLoading>());
  });

  test(
      'keeps only alerts within the radius AND the time window, excluding '
      'ones missing coordinates', () async {
    final api = _FakeAlertsApi(
      alerts: [_nearRecent, _nearButOld, _farButRecent, _noCoords],
    );
    final container = _containerWith(api);
    addTearDown(container.dispose);

    await container
        .read(alertHistoryControllerProvider.notifier)
        .load(_lat, _lon, 'Bengaluru, India');

    final state = container.read(alertHistoryControllerProvider) as AlertHistoryLoaded;
    expect(state.alerts, [_nearRecent]);
    expect(state.locationName, 'Bengaluru, India');
  });

  test('an empty result is a valid loaded state, not an error', () async {
    final container = _containerWith(_FakeAlertsApi(alerts: const []));
    addTearDown(container.dispose);

    await container
        .read(alertHistoryControllerProvider.notifier)
        .load(_lat, _lon, 'Bengaluru, India');

    final state = container.read(alertHistoryControllerProvider) as AlertHistoryLoaded;
    expect(state.alerts, isEmpty);
  });

  test('sorts newest first', () async {
    final older = AlertSummary(
      id: 5,
      severity: 'Yellow',
      eventType: 'Fog',
      areaDescription: 'Bengaluru Urban',
      latitude: _lat,
      longitude: _lon,
      fetchedAt: _isoDaysAgo(3),
    );
    final api = _FakeAlertsApi(alerts: [older, _nearRecent]);
    final container = _containerWith(api);
    addTearDown(container.dispose);

    await container
        .read(alertHistoryControllerProvider.notifier)
        .load(_lat, _lon, 'Bengaluru, India');

    final state = container.read(alertHistoryControllerProvider) as AlertHistoryLoaded;
    expect(state.alerts.map((a) => a.id), [_nearRecent.id, older.id]);
  });

  test('surfaces the real AppError on failure', () async {
    final container =
        _containerWith(_FakeAlertsApi(error: const NetworkConnectionError()));
    addTearDown(container.dispose);

    await container
        .read(alertHistoryControllerProvider.notifier)
        .load(_lat, _lon, 'Bengaluru, India');

    final state = container.read(alertHistoryControllerProvider) as AlertHistoryError;
    expect(state.error, isA<NetworkConnectionError>());
  });

  test('retry() re-issues the fetch for the same location', () async {
    var shouldFail = true;
    final api = _SwitchableAlertsApi(() => shouldFail);
    final container = _containerWith(api);
    addTearDown(container.dispose);

    await container
        .read(alertHistoryControllerProvider.notifier)
        .load(_lat, _lon, 'Bengaluru, India');
    expect(container.read(alertHistoryControllerProvider), isA<AlertHistoryError>());

    shouldFail = false;
    await container.read(alertHistoryControllerProvider.notifier).retry();

    final state = container.read(alertHistoryControllerProvider) as AlertHistoryLoaded;
    expect(state.alerts, [_nearRecent]);
  });
}

class _SwitchableAlertsApi implements AlertsApi {
  _SwitchableAlertsApi(this.shouldFail);
  final bool Function() shouldFail;

  @override
  Future<List<AlertSummary>> fetchAlerts() async {
    if (shouldFail()) throw const NetworkConnectionError();
    return [_nearRecent];
  }
}
