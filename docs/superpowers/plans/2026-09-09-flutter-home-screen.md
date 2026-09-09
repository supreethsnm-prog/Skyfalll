# Home Screen (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the real Home screen — current conditions, nearby alerts, a forecast preview, and a location switcher — replacing the `/home` route's placeholder.

**Architecture:** A `data/` layer (`WeatherApi`, `AlertsApi`, `GeocodingApi`, a `geo.dart` distance helper) mirroring Phase 1's `ChatApi` pattern exactly, a Riverpod `Notifier`-based controller holding a sealed UI state, presentational widgets (conditions card, forecast strip, alert banner), a location-search modal, and a screen composing them.

**Tech Stack:** Flutter (already installed), `flutter_riverpod`, `dio`, `go_router` — all already in `pubspec.yaml`. No new packages.

**Spec:** `docs/superpowers/specs/2026-09-08-flutter-frontend-design.md` §6c (Home design), §6b (no emulator — golden tests instead). Backend contract: `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md`, `backend/app/main.py`'s `/weather`/`/forecast`/`/alerts`/`/geocode` routes, `backend/app/geo.py`.

## Global Constraints

- No backend files touched. No new dependencies beyond what's already installed.
- Every shell command dot-sources `frontend/dev-env.ps1` from the worktree root first (`. .\frontend\dev-env.ps1`).
- No Android emulator on this hardware — visual verification is via golden-image tests only (Task 6).
- **No fabricated data fields.** `GET /weather` has no "feels like"/apparent-temperature field — an earlier design draft assumed one; it does not exist. Show only what the API actually returns.
- **Exact backend column types, verified against `backend/app/models.py`**: `humidity_pct` and `wind_direction_deg` are `Float` (`double` in Dart), NOT integers — a plan draft of this got this wrong once; do not repeat it. `weather_code` (both weather and forecast), `temp_max_c`, `temp_min_c`, `temperature_c`, `wind_speed_kmh`/`wind_speed_max_kmh` are as their names suggest (int for codes, double for measurements).
- `haversineKm` must mirror `backend/app/geo.py`'s exact formula (Earth radius 6371.0 km, same intermediate steps) — not merely "a" correct haversine implementation, so a reviewer can trace it step-by-step against the backend and confirm equivalence.
- The default starting location is a real, named, correctly-coordinated Indian city (New Delhi, 28.6139/77.2090) — never a placeholder pair like (0,0).
- Alerts with a null `latitude`/`longitude` are excluded from distance filtering, never crash the filter.
- A 404 from `GET /geocode` means "not found" (return `null`), never a generic error.
- `AppColors.alertSeverity`/`onAlertSeverity`, `AppTypography`, `AppSpacing`, `AppRadius`, `AppTheme`, `buildApiClient`, `guardApi`, `AppError` and its subtypes, `AppPrimaryButton`, `AppChip`, `LoadingView`, `ErrorView`, `EmptyView`, `weatherIconFor`, `appRouter`, and `chatControllerProvider`/`ChatController.sendMessage` all already exist and are merged — read them, don't redefine them.

---

### Task 1: Home data layer

**Files:**
- Create: `frontend/weathergpt_app/lib/core/geo.dart`
- Create: `frontend/weathergpt_app/lib/data/weather_api.dart`
- Create: `frontend/weathergpt_app/lib/data/alerts_api.dart`
- Create: `frontend/weathergpt_app/lib/data/geocoding_api.dart`
- Test: `frontend/weathergpt_app/test/core/geo_test.dart`
- Test: `frontend/weathergpt_app/test/data/weather_api_test.dart`
- Test: `frontend/weathergpt_app/test/data/alerts_api_test.dart`
- Test: `frontend/weathergpt_app/test/data/geocoding_api_test.dart`

**Interfaces:**
- Consumes: `buildApiClient()`, `guardApi<T>()`, `AppError`/`ServerError` from `lib/core/network/`.
- Produces: `double haversineKm(double lat1, double lon1, double lat2, double lon2)`; `CurrentWeather(temperatureC, humidityPct, weatherCode, windSpeedKmh, windDirectionDeg, observedAt, timezone)` + `CurrentWeather.fromJson`; `ForecastDay(forecastDate, weatherCode, tempMaxC, tempMinC)` + `ForecastDay.fromJson`; `class WeatherApi(Dio)` with `fetchCurrent(double lat, double lon) -> Future<CurrentWeather>` and `fetchForecast(double lat, double lon, {int days = 5}) -> Future<List<ForecastDay>>`; `AlertSummary(id, severity, eventType, areaDescription, latitude, longitude)` + `AlertSummary.fromJson`; `class AlertsApi(Dio)` with `fetchAlerts() -> Future<List<AlertSummary>>`; `GeocodeResult(displayName, latitude, longitude, country, state)` + `GeocodeResult.fromJson`; `class GeocodingApi(Dio)` with `search(String query) -> Future<GeocodeResult?>` (null on a 404). All consumed by Task 2's controller.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/core/geo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/geo.dart';

void main() {
  test('distance from a point to itself is zero', () {
    expect(haversineKm(28.6139, 77.2090, 28.6139, 77.2090), 0.0);
  });

  test('distance between New Delhi and Mumbai is a few hundred to ~1300km (real great-circle range)', () {
    // New Delhi (28.6139, 77.2090) and Mumbai (19.0760, 72.8777) —
    // real coordinates, not invented. The great-circle distance
    // between these two cities is well-documented to fall in this
    // range; asserting a wide-but-real range rather than a single
    // exact figure keeps this test meaningful without depending on
    // an unverifiable precise value.
    final distance = haversineKm(28.6139, 77.2090, 19.0760, 72.8777);
    expect(distance, inInclusiveRange(1000, 1300));
  });

  test('is symmetric (A to B equals B to A)', () {
    final ab = haversineKm(28.6139, 77.2090, 19.0760, 72.8777);
    final ba = haversineKm(19.0760, 72.8777, 28.6139, 77.2090);
    expect(ab, closeTo(ba, 0.001));
  });
}
```

Create `frontend/weathergpt_app/test/data/weather_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/weather_api.dart';

void main() {
  group('CurrentWeather.fromJson', () {
    test('parses a real-shaped weather response', () {
      final weather = CurrentWeather.fromJson({
        'latitude': 28.61,
        'longitude': 77.21,
        'temperature_c': 32.5,
        'humidity_pct': 41.0,
        'weather_code': 3,
        'wind_speed_kmh': 12.4,
        'wind_direction_deg': 270.0,
        'observed_at': '2026-09-09T10:00:00Z',
        'timezone': 'Asia/Kolkata',
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(weather.temperatureC, 32.5);
      expect(weather.humidityPct, 41.0);
      expect(weather.weatherCode, 3);
      expect(weather.windSpeedKmh, 12.4);
      expect(weather.windDirectionDeg, 270.0);
      expect(weather.observedAt, '2026-09-09T10:00:00Z');
      expect(weather.timezone, 'Asia/Kolkata');
    });

    test('accepts a whole-number humidity/wind-direction sent as an int-shaped JSON number', () {
      // humidity_pct and wind_direction_deg are Float columns in the
      // backend (backend/app/models.py) — a whole-number value like
      // 40 may arrive as a JSON integer literal depending on the
      // serializer. fromJson must not assume `is double` fails on
      // an int-shaped number.
      final weather = CurrentWeather.fromJson({
        'latitude': 28.61,
        'longitude': 77.21,
        'temperature_c': 32,
        'humidity_pct': 40,
        'weather_code': 0,
        'wind_speed_kmh': 10,
        'wind_direction_deg': 90,
        'observed_at': '2026-09-09T10:00:00Z',
        'timezone': 'Asia/Kolkata',
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(weather.humidityPct, 40.0);
      expect(weather.windDirectionDeg, 90.0);
    });
  });

  group('ForecastDay.fromJson', () {
    test('parses a real-shaped forecast day', () {
      final day = ForecastDay.fromJson({
        'latitude': 28.61,
        'longitude': 77.21,
        'forecast_date': '2026-09-10',
        'weather_code': 61,
        'temp_max_c': 30.0,
        'temp_min_c': 22.5,
        'precip_probability_pct': 60.0,
        'precip_sum_mm': 5.2,
        'wind_speed_max_kmh': 18.0,
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(day.forecastDate, '2026-09-10');
      expect(day.weatherCode, 61);
      expect(day.tempMaxC, 30.0);
      expect(day.tempMinC, 22.5);
    });
  });
}
```

Create `frontend/weathergpt_app/test/data/alerts_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/alerts_api.dart';

void main() {
  group('AlertSummary.fromJson', () {
    test('parses a real-shaped alert with coordinates', () {
      final alert = AlertSummary.fromJson({
        'id': 1,
        'external_id': 'SACHET-123',
        'source': 'SACHET',
        'severity': 'Severe',
        'event_type': 'Flood',
        'area_description': 'Coastal Odisha',
        'effective_start_time': '2026-09-09T00:00:00Z',
        'effective_end_time': '2026-09-10T00:00:00Z',
        'warning_message': 'Heavy rainfall expected.',
        'latitude': 20.27,
        'longitude': 85.84,
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(alert.id, 1);
      expect(alert.severity, 'Severe');
      expect(alert.eventType, 'Flood');
      expect(alert.areaDescription, 'Coastal Odisha');
      expect(alert.latitude, 20.27);
      expect(alert.longitude, 85.84);
    });

    test('parses an alert with null coordinates without throwing', () {
      final alert = AlertSummary.fromJson({
        'id': 2,
        'external_id': 'SACHET-124',
        'source': 'SACHET',
        'severity': 'Moderate',
        'event_type': 'Heatwave',
        'area_description': null,
        'effective_start_time': null,
        'effective_end_time': null,
        'warning_message': null,
        'latitude': null,
        'longitude': null,
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(alert.latitude, isNull);
      expect(alert.longitude, isNull);
    });
  });
}
```

Create `frontend/weathergpt_app/test/data/geocoding_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';

void main() {
  group('GeocodeResult.fromJson', () {
    test('parses a real-shaped geocode response', () {
      final result = GeocodeResult.fromJson({
        'query': 'mumbai',
        'display_name': 'Mumbai, Maharashtra, India',
        'latitude': 19.0760,
        'longitude': 72.8777,
        'country': 'India',
        'state': 'Maharashtra',
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(result.displayName, 'Mumbai, Maharashtra, India');
      expect(result.latitude, 19.0760);
      expect(result.longitude, 72.8777);
      expect(result.country, 'India');
      expect(result.state, 'Maharashtra');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test test\core\geo_test.dart test\data
```

Expected: FAIL — none of the four source files exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/core/geo.dart`:

```dart
import 'dart:math' as math;

const double _earthRadiusKm = 6371.0;

/// Great-circle distance between two lat/lon points, in kilometers.
/// Mirrors backend/app/geo.py's `haversine_km` exactly — same formula,
/// same Earth radius constant — so client-side alert-distance
/// filtering agrees with what the backend would compute for the same
/// coordinates.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) * math.cos(phi2) * math.sin(dLambda / 2) * math.sin(dLambda / 2);
  return 2 * _earthRadiusKm * math.asin(math.sqrt(a));
}
```

Create `frontend/weathergpt_app/lib/data/weather_api.dart`:

```dart
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// Converts a JSON number to double regardless of whether it arrived
/// as an int-shaped or double-shaped literal — `humidity_pct` and
/// `wind_direction_deg` are Float columns in the backend
/// (backend/app/models.py) but a whole-number value can arrive as a
/// JSON integer depending on serialization.
double _asDouble(dynamic value) => (value as num).toDouble();

class CurrentWeather {
  final double temperatureC;
  final double humidityPct;
  final int weatherCode;
  final double windSpeedKmh;
  final double windDirectionDeg;
  final String observedAt;
  final String timezone;

  const CurrentWeather({
    required this.temperatureC,
    required this.humidityPct,
    required this.weatherCode,
    required this.windSpeedKmh,
    required this.windDirectionDeg,
    required this.observedAt,
    required this.timezone,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    return CurrentWeather(
      temperatureC: _asDouble(json['temperature_c']),
      humidityPct: _asDouble(json['humidity_pct']),
      weatherCode: json['weather_code'] as int,
      windSpeedKmh: _asDouble(json['wind_speed_kmh']),
      windDirectionDeg: _asDouble(json['wind_direction_deg']),
      observedAt: json['observed_at'] as String,
      timezone: json['timezone'] as String,
    );
  }
}

class ForecastDay {
  final String forecastDate;
  final int weatherCode;
  final double tempMaxC;
  final double tempMinC;

  const ForecastDay({
    required this.forecastDate,
    required this.weatherCode,
    required this.tempMaxC,
    required this.tempMinC,
  });

  factory ForecastDay.fromJson(Map<String, dynamic> json) {
    return ForecastDay(
      forecastDate: json['forecast_date'] as String,
      weatherCode: json['weather_code'] as int,
      tempMaxC: _asDouble(json['temp_max_c']),
      tempMinC: _asDouble(json['temp_min_c']),
    );
  }
}

/// Wraps `GET /weather` and `GET /forecast`.
class WeatherApi {
  final Dio _dio;

  WeatherApi(this._dio);

  Future<CurrentWeather> fetchCurrent(double lat, double lon) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/weather',
        queryParameters: {'lat': lat, 'lon': lon},
      );
      return CurrentWeather.fromJson(response.data!);
    });
  }

  Future<List<ForecastDay>> fetchForecast(
    double lat,
    double lon, {
    int days = 5,
  }) {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>(
        '/forecast',
        queryParameters: {'lat': lat, 'lon': lon, 'days': days},
      );
      return response.data!
          .map((entry) => ForecastDay.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }
}
```

Create `frontend/weathergpt_app/lib/data/alerts_api.dart`:

```dart
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

class AlertSummary {
  final int id;
  final String severity;
  final String eventType;
  final String? areaDescription;
  final double? latitude;
  final double? longitude;

  const AlertSummary({
    required this.id,
    required this.severity,
    required this.eventType,
    required this.areaDescription,
    required this.latitude,
    required this.longitude,
  });

  factory AlertSummary.fromJson(Map<String, dynamic> json) {
    return AlertSummary(
      id: json['id'] as int,
      severity: json['severity'] as String,
      eventType: json['event_type'] as String,
      areaDescription: json['area_description'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// Wraps `GET /alerts`. Note: this endpoint returns EVERY alert
/// nationwide — it does not accept lat/lon filtering (a known,
/// pre-existing backend gap, not fixed by this branch). Distance
/// filtering happens client-side — see HomeController.
class AlertsApi {
  final Dio _dio;

  AlertsApi(this._dio);

  Future<List<AlertSummary>> fetchAlerts() {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>('/alerts');
      return response.data!
          .map((entry) => AlertSummary.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }
}
```

Create `frontend/weathergpt_app/lib/data/geocoding_api.dart`:

```dart
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/app_error.dart';

class GeocodeResult {
  final String displayName;
  final double latitude;
  final double longitude;
  final String? country;
  final String? state;

  const GeocodeResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.country,
    required this.state,
  });

  factory GeocodeResult.fromJson(Map<String, dynamic> json) {
    return GeocodeResult(
      displayName: json['display_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      country: json['country'] as String?,
      state: json['state'] as String?,
    );
  }
}

/// Wraps `GET /geocode`. A 404 (no match) is a normal, expected
/// outcome — not an error — so [search] returns null rather than
/// throwing for that specific case.
class GeocodingApi {
  final Dio _dio;

  GeocodingApi(this._dio);

  Future<GeocodeResult?> search(String query) async {
    try {
      return await guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/geocode',
          queryParameters: {'q': query},
        );
        return GeocodeResult.fromJson(response.data!);
      });
    } on ServerError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\core\geo_test.dart test\data
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/core/geo.dart frontend/weathergpt_app/lib/data/weather_api.dart frontend/weathergpt_app/lib/data/alerts_api.dart frontend/weathergpt_app/lib/data/geocoding_api.dart frontend/weathergpt_app/test/core/geo_test.dart frontend/weathergpt_app/test/data/weather_api_test.dart frontend/weathergpt_app/test/data/alerts_api_test.dart frontend/weathergpt_app/test/data/geocoding_api_test.dart
git commit -m "feat: add Home data layer (weather, alerts, geocoding APIs, haversine)"
```

---

### Task 2: Home state controller

**Files:**
- Create: `frontend/weathergpt_app/lib/features/home/home_controller.dart`
- Test: `frontend/weathergpt_app/test/features/home/home_controller_test.dart`

**Interfaces:**
- Consumes: `haversineKm` (Task 1); `CurrentWeather`, `ForecastDay`, `WeatherApi` (Task 1); `AlertSummary`, `AlertsApi` (Task 1); `GeocodeResult`, `GeocodingApi` (Task 1); `buildApiClient()` (Phase 0).
- Produces: sealed `HomeUiState` with subtypes `HomeLoading()`, `HomeLoaded(GeocodeResult location, CurrentWeather weather, List<ForecastDay> forecast, List<AlertSummary> nearbyAlerts)`, `HomeError(AppError error)`; `class HomeController extends Notifier<HomeUiState>` with `Future<void> loadInitial()`, `Future<void> changeLocation(GeocodeResult location)`, `Future<void> retry()`; providers `weatherApiProvider`, `alertsApiProvider`, `geocodingApiProvider` (this last one has no consumer within this task itself — it's defined here alongside its siblings for a single, obvious place to find every API provider, and is consumed starting in Task 4), `homeControllerProvider`. All consumed by Task 5's screen and Task 6's golden test.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/features/home/home_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

const _newDelhi = GeocodeResult(
  displayName: 'New Delhi, India',
  latitude: 28.6139,
  longitude: 77.2090,
  country: 'India',
  state: 'Delhi',
);

const _sampleWeather = CurrentWeather(
  temperatureC: 32.0,
  humidityPct: 40.0,
  weatherCode: 0,
  windSpeedKmh: 10.0,
  windDirectionDeg: 90.0,
  observedAt: '2026-09-09T10:00:00Z',
  timezone: 'Asia/Kolkata',
);

const _sampleForecast = [
  ForecastDay(forecastDate: '2026-09-10', weatherCode: 61, tempMaxC: 30.0, tempMinC: 22.0),
];

// A real Delhi-area coordinate (well within 100km) and a real,
// clearly-far-away coordinate (Chennai, ~1750km from Delhi) so the
// distance filtering test exercises genuinely different outcomes.
const _nearbyAlert = AlertSummary(
  id: 1,
  severity: 'Moderate',
  eventType: 'Heatwave',
  areaDescription: 'Delhi NCR',
  latitude: 28.7,
  longitude: 77.1,
);
const _farAlert = AlertSummary(
  id: 2,
  severity: 'Severe',
  eventType: 'Flood',
  areaDescription: 'Chennai',
  latitude: 13.0827,
  longitude: 80.2707,
);
const _noCoordsAlert = AlertSummary(
  id: 3,
  severity: 'Minor',
  eventType: 'Fog',
  areaDescription: null,
  latitude: null,
  longitude: null,
);

class FakeWeatherApi implements WeatherApi {
  CurrentWeather? nextWeather;
  AppError? nextWeatherError;
  final List<List<double>> fetchCurrentCalls = [];

  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    fetchCurrentCalls.add([lat, lon]);
    if (nextWeatherError != null) throw nextWeatherError!;
    return nextWeather!;
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon, {int days = 5}) async {
    return _sampleForecast;
  }
}

class FakeAlertsApi implements AlertsApi {
  List<AlertSummary> nextAlerts = const [];

  @override
  Future<List<AlertSummary>> fetchAlerts() async => nextAlerts;
}

void main() {
  late FakeWeatherApi fakeWeatherApi;
  late FakeAlertsApi fakeAlertsApi;
  late ProviderContainer container;

  setUp(() {
    fakeWeatherApi = FakeWeatherApi()..nextWeather = _sampleWeather;
    fakeAlertsApi = FakeAlertsApi()..nextAlerts = [_nearbyAlert, _farAlert, _noCoordsAlert];
    container = ProviderContainer(
      overrides: [
        weatherApiProvider.overrideWithValue(fakeWeatherApi),
        alertsApiProvider.overrideWithValue(fakeAlertsApi),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('starts in HomeLoading', () {
    expect(container.read(homeControllerProvider), isA<HomeLoading>());
  });

  test('loadInitial fetches for New Delhi and populates HomeLoaded', () async {
    await container.read(homeControllerProvider.notifier).loadInitial();

    final state = container.read(homeControllerProvider);
    expect(state, isA<HomeLoaded>());
    final loaded = state as HomeLoaded;
    expect(loaded.location.displayName, contains('Delhi'));
    expect(loaded.weather.temperatureC, 32.0);
    expect(loaded.forecast, hasLength(1));
    expect(fakeWeatherApi.fetchCurrentCalls.single, [28.6139, 77.2090]);
  });

  test('loadInitial filters alerts to within 100km, excluding the far one and the one with no coordinates', () async {
    await container.read(homeControllerProvider.notifier).loadInitial();

    final loaded = container.read(homeControllerProvider) as HomeLoaded;
    expect(loaded.nearbyAlerts, hasLength(1));
    expect(loaded.nearbyAlerts.single.id, 1);
  });

  test('changeLocation re-fetches for the new coordinates', () async {
    await container.read(homeControllerProvider.notifier).loadInitial();

    const mumbai = GeocodeResult(
      displayName: 'Mumbai, India',
      latitude: 19.0760,
      longitude: 72.8777,
      country: 'India',
      state: 'Maharashtra',
    );
    await container.read(homeControllerProvider.notifier).changeLocation(mumbai);

    final loaded = container.read(homeControllerProvider) as HomeLoaded;
    expect(loaded.location.displayName, 'Mumbai, India');
    expect(fakeWeatherApi.fetchCurrentCalls.last, [19.0760, 72.8777]);
  });

  test('a fetch failure surfaces HomeError with the real AppError', () async {
    fakeWeatherApi.nextWeatherError = const NetworkTimeoutError();

    await container.read(homeControllerProvider.notifier).loadInitial();

    final state = container.read(homeControllerProvider);
    expect(state, isA<HomeError>());
    expect((state as HomeError).error, isA<NetworkTimeoutError>());
  });

  test('retry re-issues the fetch and can recover from a prior failure', () async {
    fakeWeatherApi.nextWeatherError = const NetworkTimeoutError();
    await container.read(homeControllerProvider.notifier).loadInitial();
    expect(container.read(homeControllerProvider), isA<HomeError>());

    fakeWeatherApi.nextWeatherError = null;
    await container.read(homeControllerProvider.notifier).retry();

    expect(container.read(homeControllerProvider), isA<HomeLoaded>());
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
flutter test test\features\home\home_controller_test.dart
```

Expected: FAIL — `home_controller.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/home/home_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/geo.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
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

  const HomeLoaded({
    required this.location,
    required this.weather,
    required this.forecast,
    required this.nearbyAlerts,
  });
}

class HomeError extends HomeUiState {
  final AppError error;

  const HomeError(this.error);
}

final weatherApiProvider = Provider<WeatherApi>((ref) => WeatherApi(buildApiClient()));
final alertsApiProvider = Provider<AlertsApi>((ref) => AlertsApi(buildApiClient()));
final geocodingApiProvider = Provider<GeocodingApi>((ref) => GeocodingApi(buildApiClient()));

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
      );
    } on AppError catch (e) {
      _location = location;
      state = HomeError(e);
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\features\home\home_controller_test.dart
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/home/home_controller.dart frontend/weathergpt_app/test/features/home/
git commit -m "feat: add HomeController with concurrent fetch and alert distance filtering"
```

---

### Task 3: Presentational widgets

**Files:**
- Create: `frontend/weathergpt_app/lib/features/home/widgets/current_conditions_card.dart`
- Create: `frontend/weathergpt_app/lib/features/home/widgets/forecast_strip.dart`
- Create: `frontend/weathergpt_app/lib/features/home/widgets/alert_banner.dart`
- Test: `frontend/weathergpt_app/test/features/home/widgets/current_conditions_card_test.dart`
- Test: `frontend/weathergpt_app/test/features/home/widgets/forecast_strip_test.dart`
- Test: `frontend/weathergpt_app/test/features/home/widgets/alert_banner_test.dart`

**Interfaces:**
- Consumes: `CurrentWeather`, `ForecastDay` (Task 1); `AlertSummary` (Task 1); `AppColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `weatherIconFor` (Phase 0).
- Produces: `CurrentConditionsCard({required CurrentWeather weather})`, `ForecastStrip({required List<ForecastDay> days})`, `AlertBanner({required AlertSummary alert})` — all consumed by Task 5's screen and Task 6's golden test.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/features/home/widgets/current_conditions_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/widgets/current_conditions_card.dart';

void main() {
  testWidgets('renders the temperature, humidity, and wind speed', (tester) async {
    const weather = CurrentWeather(
      temperatureC: 32.0,
      humidityPct: 40.0,
      weatherCode: 0,
      windSpeedKmh: 10.0,
      windDirectionDeg: 90.0,
      observedAt: '2026-09-09T10:00:00Z',
      timezone: 'Asia/Kolkata',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CurrentConditionsCard(weather: weather))),
    );

    expect(find.textContaining('32'), findsWidgets);
    expect(find.textContaining('40'), findsWidgets);
    expect(find.textContaining('10'), findsWidgets);
    // Never shows a fabricated "feels like" value — there is no such field.
    expect(find.textContaining('Feels like'), findsNothing);
  });
}
```

Create `frontend/weathergpt_app/test/features/home/widgets/forecast_strip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/widgets/forecast_strip.dart';

void main() {
  testWidgets('renders one entry per forecast day', (tester) async {
    const days = [
      ForecastDay(forecastDate: '2026-09-10', weatherCode: 61, tempMaxC: 30.0, tempMinC: 22.0),
      ForecastDay(forecastDate: '2026-09-11', weatherCode: 0, tempMaxC: 33.0, tempMinC: 24.0),
    ];

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ForecastStrip(days: days))),
    );

    expect(find.textContaining('30'), findsWidgets);
    expect(find.textContaining('33'), findsWidgets);
  });

  testWidgets('renders nothing but does not crash for an empty list', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ForecastStrip(days: []))),
    );
    expect(tester.takeException(), isNull);
  });
}
```

Create `frontend/weathergpt_app/test/features/home/widgets/alert_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/features/home/widgets/alert_banner.dart';

void main() {
  testWidgets('renders the event type and area description', (tester) async {
    const alert = AlertSummary(
      id: 1,
      severity: 'Severe',
      eventType: 'Flood',
      areaDescription: 'Coastal Odisha',
      latitude: 20.27,
      longitude: 85.84,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AlertBanner(alert: alert))),
    );

    expect(find.textContaining('Flood'), findsOneWidget);
    expect(find.textContaining('Coastal Odisha'), findsOneWidget);
  });

  testWidgets('uses AppColors.alertSeverity for its background color', (tester) async {
    const alert = AlertSummary(
      id: 1,
      severity: 'Extreme',
      eventType: 'Cyclone',
      areaDescription: 'Puri',
      latitude: 19.8,
      longitude: 85.8,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AlertBanner(alert: alert))),
    );

    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, AppColors.alertSeverity('Extreme'));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
flutter test test\features\home\widgets
```

Expected: FAIL — none of the three widgets exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/home/widgets/current_conditions_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/weather_api.dart';
import '../../../shared/widgets/weather_icon.dart';

/// The Home screen's hero module. Shows only fields the backend
/// actually returns — there is no "feels like"/apparent-temperature
/// value in `GET /weather`'s response, so none is shown here.
class CurrentConditionsCard extends StatelessWidget {
  final CurrentWeather weather;

  const CurrentConditionsCard({super.key, required this.weather});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(weatherIconFor(weather.weatherCode), size: 48, color: onSurface),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${weather.temperatureC.round()}°C',
                style: AppTypography.display(onSurface),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Humidity ${weather.humidityPct.round()}% · Wind ${weather.windSpeedKmh.round()} km/h',
                style: AppTypography.body(secondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/features/home/widgets/forecast_strip.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/weather_api.dart';
import '../../../shared/widgets/weather_icon.dart';

/// A short horizontal preview of upcoming days — not the full
/// multi-day forecast view (that's a dedicated Forecast screen, a
/// later phase).
class ForecastStrip extends StatelessWidget {
  final List<ForecastDay> days;

  const ForecastStrip({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: days.length,
        separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final day = days[index];
          return Container(
            width: 72,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.surface),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(weatherIconFor(day.weatherCode), color: onSurface),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${day.tempMaxC.round()}° / ${day.tempMinC.round()}°',
                  style: AppTypography.caption(onSurface),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/features/home/widgets/alert_banner.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/alerts_api.dart';

class AlertBanner extends StatelessWidget {
  final AlertSummary alert;

  const AlertBanner({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = AppColors.alertSeverity(alert.severity);
    final textColor = AppColors.onAlertSeverity(alert.severity);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.surface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(alert.eventType, style: AppTypography.title(textColor)),
          if (alert.areaDescription != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(alert.areaDescription!, style: AppTypography.body(textColor)),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\features\home\widgets
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/home/widgets/ frontend/weathergpt_app/test/features/home/widgets/
git commit -m "feat: add current-conditions card, forecast strip, and alert banner widgets"
```

---

### Task 4: Location search modal

**Files:**
- Create: `frontend/weathergpt_app/lib/features/home/widgets/location_search_sheet.dart`
- Test: `frontend/weathergpt_app/test/features/home/widgets/location_search_sheet_test.dart`

**Interfaces:**
- Consumes: `GeocodeResult`, `GeocodingApi` (Task 1); `geocodingApiProvider` (Task 2); `AppPrimaryButton`, `ErrorView` (Phase 0).
- Produces: `Future<GeocodeResult?> showLocationSearchSheet(BuildContext context, WidgetRef ref)` (a function opening a modal bottom sheet, returning the confirmed result or null if dismissed) — consumed by Task 5's screen.

Plan author's choice, documented here: a modal **bottom sheet** (via `showModalBottomSheet`) rather than a full-screen route or a `Dialog`, since it's a quick, dismissible, single-purpose interaction that doesn't need its own place in navigation history.

- [ ] **Step 1: Write the failing test**

Create `frontend/weathergpt_app/test/features/home/widgets/location_search_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/home/widgets/location_search_sheet.dart';

class FakeGeocodingApi implements GeocodingApi {
  GeocodeResult? nextResult;
  bool throwGeneric = false;

  @override
  Future<GeocodeResult?> search(String query) async {
    if (throwGeneric) throw const FormatException('boom');
    return nextResult;
  }
}

Widget _wrap(FakeGeocodingApi fakeApi, Widget child) {
  return ProviderScope(
    overrides: [geocodingApiProvider.overrideWithValue(fakeApi)],
    child: MaterialApp(home: Scaffold(body: Builder(builder: (context) => child))),
  );
}

void main() {
  testWidgets('a found location can be searched and confirmed', (tester) async {
    final fakeApi = FakeGeocodingApi()
      ..nextResult = const GeocodeResult(
        displayName: 'Mumbai, India',
        latitude: 19.0760,
        longitude: 72.8777,
        country: 'India',
        state: 'Maharashtra',
      );

    GeocodeResult? confirmed;

    await tester.pumpWidget(
      _wrap(
        fakeApi,
        Consumer(
          builder: (context, ref, _) => AppPrimaryButtonTestTrigger(
            onPressed: () async {
              confirmed = await showLocationSearchSheet(context, ref);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppPrimaryButtonTestTrigger));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Mumbai');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Mumbai, India'), findsOneWidget);

    await tester.tap(find.text('Use this location'));
    await tester.pumpAndSettle();

    expect(confirmed?.displayName, 'Mumbai, India');
  });

  testWidgets('a not-found query shows a "not found" message, not a generic error', (tester) async {
    final fakeApi = FakeGeocodingApi()..nextResult = null;

    await tester.pumpWidget(
      _wrap(
        fakeApi,
        Consumer(
          builder: (context, ref, _) => AppPrimaryButtonTestTrigger(
            onPressed: () => showLocationSearchSheet(context, ref),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppPrimaryButtonTestTrigger));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Nowhereville');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not found', findRichText: true), findsOneWidget);
  });

  testWidgets('a generic failure shows an error view', (tester) async {
    final fakeApi = FakeGeocodingApi()..throwGeneric = true;

    await tester.pumpWidget(
      _wrap(
        fakeApi,
        Consumer(
          builder: (context, ref, _) => AppPrimaryButtonTestTrigger(
            onPressed: () => showLocationSearchSheet(context, ref),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppPrimaryButtonTestTrigger));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Anywhere');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });
}

/// Minimal test-only trigger widget — the real screen calls
/// `showLocationSearchSheet` directly from a tap handler (see Task 5);
/// this stand-in exists only so the test has a concrete widget to tap
/// that owns a `BuildContext`/`WidgetRef` to pass through.
class AppPrimaryButtonTestTrigger extends StatelessWidget {
  final VoidCallback onPressed;
  const AppPrimaryButtonTestTrigger({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(onPressed: onPressed, child: const Text('Open'));
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
flutter test test\features\home\widgets\location_search_sheet_test.dart
```

Expected: FAIL — `location_search_sheet.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/home/widgets/location_search_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/geocoding_api.dart';
import '../../../shared/widgets/app_primary_button.dart';
import '../../../shared/widgets/error_view.dart';
import '../home_controller.dart';

/// Opens a modal bottom sheet letting the user search for and confirm
/// a new location via `GET /geocode`. Returns the confirmed
/// [GeocodeResult], or null if the sheet was dismissed without one.
Future<GeocodeResult?> showLocationSearchSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<GeocodeResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LocationSearchSheet(ref: ref),
  );
}

class _LocationSearchSheet extends StatefulWidget {
  final WidgetRef ref;
  const _LocationSearchSheet({required this.ref});

  @override
  State<_LocationSearchSheet> createState() => _LocationSearchSheetState();
}

sealed class _SearchState {}
class _SearchIdle implements _SearchState {}
class _SearchLoading implements _SearchState {}
class _SearchFound implements _SearchState {
  final GeocodeResult result;
  _SearchFound(this.result);
}
class _SearchNotFound implements _SearchState {}
class _SearchFailed implements _SearchState {
  final Object error;
  _SearchFailed(this.error);
}

class _LocationSearchSheetState extends State<_LocationSearchSheet> {
  final _controller = TextEditingController();
  _SearchState _state = _SearchIdle();

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() => _state = _SearchLoading());
    try {
      final api = widget.ref.read(geocodingApiProvider);
      final result = await api.search(query);
      setState(() => _state = result == null ? _SearchNotFound() : _SearchFound(result));
    } catch (e) {
      setState(() => _state = _SearchFailed(e));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Search for a city…'),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(label: 'Search', onPressed: _search),
          const SizedBox(height: AppSpacing.md),
          _buildResult(context),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final state = _state;
    return switch (state) {
      _SearchIdle() => const SizedBox.shrink(),
      _SearchLoading() => const Center(child: CircularProgressIndicator()),
      _SearchFound(:final result) => Column(
          children: [
            Text(result.displayName, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.sm),
            AppPrimaryButton(
              label: 'Use this location',
              onPressed: () => Navigator.of(context).pop(result),
            ),
          ],
        ),
      _SearchNotFound() => Text(
          "We couldn't find that location. Try a different search.",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      _SearchFailed() => ErrorView(
          message: 'Search failed. Please try again.',
          onRetry: _search,
        ),
    };
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\features\home\widgets\location_search_sheet_test.dart
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/home/widgets/location_search_sheet.dart frontend/weathergpt_app/test/features/home/widgets/location_search_sheet_test.dart
git commit -m "feat: add location search bottom sheet"
```

---

### Task 5: Home screen and router wiring

**Files:**
- Create: `frontend/weathergpt_app/lib/features/home/home_screen.dart`
- Modify: `frontend/weathergpt_app/lib/core/router/app_router.dart`
- Test: `frontend/weathergpt_app/test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `homeControllerProvider`, `HomeUiState`/`HomeLoading`/`HomeLoaded`/`HomeError` (Task 2); `CurrentConditionsCard`, `ForecastStrip`, `AlertBanner` (Task 3); `showLocationSearchSheet` (Task 4); `LoadingView`, `ErrorView`, `AppChip` (Phase 0); `chatControllerProvider` (Phase 1 — read `frontend/weathergpt_app/lib/features/chat/chat_controller.dart` to confirm `ChatController.sendMessage(String)`'s exact signature).
- Produces: `HomeScreen` (a `ConsumerStatefulWidget`, since it needs to trigger `loadInitial()` once via `initState`), wired into `appRouter`'s `/home` branch.

**Cross-tab send mechanism**: `chatControllerProvider` is a global Riverpod provider (defined in `chat_controller.dart`, not scoped to `ChatScreen`'s widget tree) — any widget anywhere under the app's `ProviderScope` can call `ref.read(chatControllerProvider.notifier).sendMessage(question)` directly. Home's quick-action chips do exactly that, then navigate: `context.go('/chat')`. This requires no new plumbing and no changes to `chat_controller.dart`/`chat_screen.dart`.

- [ ] **Step 1: Write the failing test**

Create `frontend/weathergpt_app/test/features/home/home_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/alerts_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/home/home_screen.dart';

class FakeWeatherApi implements WeatherApi {
  @override
  Future<CurrentWeather> fetchCurrent(double lat, double lon) async {
    return const CurrentWeather(
      temperatureC: 30.0,
      humidityPct: 45.0,
      weatherCode: 0,
      windSpeedKmh: 8.0,
      windDirectionDeg: 180.0,
      observedAt: '2026-09-09T10:00:00Z',
      timezone: 'Asia/Kolkata',
    );
  }

  @override
  Future<List<ForecastDay>> fetchForecast(double lat, double lon, {int days = 5}) async {
    return const [
      ForecastDay(forecastDate: '2026-09-10', weatherCode: 3, tempMaxC: 31.0, tempMinC: 23.0),
    ];
  }
}

class FakeAlertsApi implements AlertsApi {
  @override
  Future<List<AlertSummary>> fetchAlerts() async => const [];
}

class FakeGeocodingApi implements GeocodingApi {
  @override
  Future<GeocodeResult?> search(String query) async => null;
}

void main() {
  testWidgets('loads on mount and renders the current temperature', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weatherApiProvider.overrideWithValue(FakeWeatherApi()),
          alertsApiProvider.overrideWithValue(FakeAlertsApi()),
          geocodingApiProvider.overrideWithValue(FakeGeocodingApi()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pump(); // let loadInitial's Future.wait resolve
    await tester.pump();

    expect(find.textContaining('30'), findsWidgets);
    expect(find.textContaining('New Delhi'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
flutter test test\features\home\home_screen_test.dart
```

Expected: FAIL — `home_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/home/home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/app_error.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_chip.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../chat/chat_controller.dart';
import 'home_controller.dart';
import 'widgets/alert_banner.dart';
import 'widgets/current_conditions_card.dart';
import 'widgets/forecast_strip.dart';
import 'widgets/location_search_sheet.dart';

const _quickActions = [
  'Any alerts near me?',
  'Will it rain tomorrow?',
  'Is it safe to travel today?',
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(homeControllerProvider.notifier).loadInitial());
  }

  String _describeError(AppError error) => switch (error) {
        NetworkTimeoutError() =>
          'That took too long — check your connection and try again.',
        NetworkConnectionError() =>
          'Could not reach the server. Check your connection and try again.',
        ServerError(:final statusCode) =>
          'The server had a problem (code $statusCode). Try again in a moment.',
        UnknownError() => 'Something went wrong. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (state) {
          HomeLoaded(:final location) => location.displayName,
          _ => 'Home',
        }),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final picked = await showLocationSearchSheet(context, ref);
              if (picked != null) {
                await controller.changeLocation(picked);
              }
            },
          ),
        ],
      ),
      body: switch (state) {
        HomeLoading() => const LoadingView(message: 'Loading conditions…'),
        HomeError(:final error) =>
          ErrorView(message: _describeError(error), onRetry: controller.retry),
        HomeLoaded(:final weather, :final forecast, :final nearbyAlerts) => ListView(
            children: [
              for (final alert in nearbyAlerts) AlertBanner(alert: alert),
              CurrentConditionsCard(weather: weather),
              ForecastStrip(days: forecast),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final question in _quickActions)
                      AppChip(
                        label: question,
                        onTap: () {
                          ref.read(chatControllerProvider.notifier).sendMessage(question);
                          context.go('/chat');
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
      },
    );
  }
}
```

- [ ] **Step 4: Wire the router**

Modify `frontend/weathergpt_app/lib/core/router/app_router.dart`: replace the `/home` branch's `PlaceholderScreen(title: 'Home')` with `HomeScreen()`, and add the import:

```dart
import '../../features/home/home_screen.dart';
```

```dart
StatefulShellBranch(
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
),
```

- [ ] **Step 5: Run the tests to verify they pass**

```powershell
flutter test test\features\home
```

- [ ] **Step 6: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/home/home_screen.dart frontend/weathergpt_app/lib/core/router/app_router.dart frontend/weathergpt_app/test/features/home/home_screen_test.dart
git commit -m "feat: add HomeScreen and wire it into the /home route"
```

---

### Task 6: Golden verification

**Files:**
- Create: `frontend/weathergpt_app/test/golden/home_screen_golden_test.dart`
- Create (generated): `frontend/weathergpt_app/test/golden/goldens/home_light.png`
- Create (generated): `frontend/weathergpt_app/test/golden/goldens/home_dark.png`

**Interfaces:**
- Consumes: `HomeScreen` (Task 5), `homeControllerProvider`/`HomeController` (Task 2), `AppTheme.light`/`AppTheme.dark` (Phase 0), the FontLoader pattern established in `test/golden/gallery_golden_test.dart` and `test/golden/chat_screen_golden_test.dart` (read one first).

- [ ] **Step 1: Read an existing golden test for the established pattern**

Open `frontend/weathergpt_app/test/golden/chat_screen_golden_test.dart` and note its `setUpAll` font-loading code and its `_Seeded...Controller extends <RealController>` override pattern (`overrideWith(() => _Seeded...(seed))`) — reuse both verbatim, adapted to `HomeController`/`HomeUiState`.

- [ ] **Step 2: Write the golden test**

Create `frontend/weathergpt_app/test/golden/home_screen_golden_test.dart`, copying the font-loading `setUpAll` from `chat_screen_golden_test.dart`, then:

```dart
// (font-loading setUpAll copied from chat_screen_golden_test.dart goes here)

class _SeededHomeController extends HomeController {
  final HomeUiState seed;
  _SeededHomeController(this.seed);

  @override
  HomeUiState build() => seed;
}

Widget _buildApp(ThemeData theme) {
  const location = GeocodeResult(
    displayName: 'New Delhi, India',
    latitude: 28.6139,
    longitude: 77.2090,
    country: 'India',
    state: 'Delhi',
  );
  const weather = CurrentWeather(
    temperatureC: 31.0,
    humidityPct: 52.0,
    weatherCode: 3,
    windSpeedKmh: 14.0,
    windDirectionDeg: 220.0,
    observedAt: '2026-09-09T10:00:00Z',
    timezone: 'Asia/Kolkata',
  );
  const forecast = [
    ForecastDay(forecastDate: '2026-09-10', weatherCode: 61, tempMaxC: 30.0, tempMinC: 23.0),
    ForecastDay(forecastDate: '2026-09-11', weatherCode: 0, tempMaxC: 33.0, tempMinC: 24.0),
    ForecastDay(forecastDate: '2026-09-12', weatherCode: 95, tempMaxC: 28.0, tempMinC: 22.0),
  ];
  const alert = AlertSummary(
    id: 1,
    severity: 'Moderate',
    eventType: 'Heavy rainfall warning',
    areaDescription: 'Delhi NCR',
    latitude: 28.7,
    longitude: 77.1,
  );
  const seeded = HomeLoaded(
    location: location,
    weather: weather,
    forecast: forecast,
    nearbyAlerts: [alert],
  );

  return ProviderScope(
    overrides: [
      homeControllerProvider.overrideWith(() => _SeededHomeController(seeded)),
    ],
    child: MaterialApp(theme: theme, home: const HomeScreen()),
  );
}

void main() {
  // ... setUpAll font loading from chat_screen_golden_test.dart ...

  testWidgets('home screen — light theme', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildApp(AppTheme.light));
    await tester.pump();

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_light.png'),
    );
  });

  testWidgets('home screen — dark theme', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildApp(AppTheme.dark));
    await tester.pump();

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_dark.png'),
    );
  });
}
```

Match the exact physical size the prior golden tests used (check the file rather than assume). Add whatever imports the file needs (`flutter_riverpod`, `weathergpt_app/core/theme/app_theme.dart`, `weathergpt_app/data/weather_api.dart`, `weathergpt_app/data/alerts_api.dart`, `weathergpt_app/data/geocoding_api.dart`, `weathergpt_app/features/home/home_controller.dart`, `weathergpt_app/features/home/home_screen.dart`).

- [ ] **Step 3: Generate the goldens**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test --update-goldens test\golden\home_screen_golden_test.dart
```

- [ ] **Step 4: Confirm determinism**

```powershell
flutter test test\golden\home_screen_golden_test.dart
```

Expected: PASS, without `--update-goldens`. If the forecast strip's `ListView.separated` or anything else introduces non-determinism (unlikely, since nothing here animates), investigate and fix before proceeding; report exactly what you found either way.

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/test/golden/home_screen_golden_test.dart frontend/weathergpt_app/test/golden/goldens/home_light.png frontend/weathergpt_app/test/golden/goldens/home_dark.png
git commit -m "test: add golden-image regression coverage for the Home screen"
```

---

## Execution

This plan is ready for **subagent-driven-development**: a fresh implementer subagent per task, a task review after each, and a final whole-branch review at the end — the approach used for every prior phase of this project.
