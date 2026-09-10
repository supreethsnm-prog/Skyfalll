import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/app_error.dart';

double? _asDoubleOrNull(dynamic value) =>
    value == null ? null : (value as num).toDouble();

/// One location's ERA5 coverage: every date `GET /historical` can be asked
/// for at this place. Backend returns dates newest-first as ISO-8601
/// strings (see `list_available_history`'s docstring), so no re-sorting is
/// needed here.
class HistoricalCoverage {
  final String locationName;
  final double latitude;
  final double longitude;
  final List<String> dates;

  const HistoricalCoverage({
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.dates,
  });

  factory HistoricalCoverage.fromJson(Map<String, dynamic> json) {
    return HistoricalCoverage(
      locationName: json['location_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      dates: (json['dates'] as List).cast<String>(),
    );
  }
}

/// A single ERA5 reanalysis reading for one location/date pair.
///
/// **`precipMm` is NOT a daily total.** It is ERA5's 1-hour accumulation
/// ending at the 12:00 UTC observation time for [observationDate] — see the
/// module docstring in `backend/app/history/service.py`. Every place this
/// value is shown must say so; treating it as "rainfall that day" would
/// overstate a monsoon figure by more than an order of magnitude.
class HistoricalReading {
  final String locationName;
  final double latitude;
  final double longitude;
  final String observationDate;

  final double? temp2mC;
  final double? dewpoint2mC;

  /// ERA5's 1-hour accumulation ending at 12:00 UTC on [observationDate].
  /// Not a daily total — see the class doc.
  final double? precipMm;

  final double? windSpeed10mKmh;
  final double? windDirection10mDeg;
  final double? mslpHpa;

  const HistoricalReading({
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.observationDate,
    this.temp2mC,
    this.dewpoint2mC,
    this.precipMm,
    this.windSpeed10mKmh,
    this.windDirection10mDeg,
    this.mslpHpa,
  });

  factory HistoricalReading.fromJson(Map<String, dynamic> json) {
    return HistoricalReading(
      locationName: json['location_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      observationDate: json['observation_date'] as String,
      temp2mC: _asDoubleOrNull(json['temp_2m_c']),
      dewpoint2mC: _asDoubleOrNull(json['dewpoint_2m_c']),
      precipMm: _asDoubleOrNull(json['precip_mm']),
      windSpeed10mKmh: _asDoubleOrNull(json['wind_speed_10m_kmh']),
      windDirection10mDeg: _asDoubleOrNull(json['wind_direction_10m_deg']),
      mslpHpa: _asDoubleOrNull(json['mslp_hpa']),
    );
  }
}

/// Wraps `GET /historical` and `GET /historical/available`.
///
/// `/historical` matches an exact location name and date against a small,
/// fixed ERA5 seed matrix (see `backend/app/history/service.py`) — there is
/// no way to discover what is seeded except by calling [fetchAvailable]
/// first, so this class deliberately offers no way to skip that step.
class HistoricalApi {
  final Dio _dio;

  HistoricalApi(this._dio);

  /// Every (location, date) pair the backend actually holds a reading for,
  /// grouped by location. Can legitimately be an empty list — the seed
  /// table is truncated by the backend's own test suite and re-seeding is
  /// expensive — which callers must treat as "no historical data loaded",
  /// not an error.
  Future<List<HistoricalCoverage>> fetchAvailable() async {
    return guardApi(() async {
      final response =
          await _dio.get<List<dynamic>>('/historical/available');
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(HistoricalCoverage.fromJson)
          .toList();
    });
  }

  /// Returns null when [location]/[date] is not a seeded pair — the
  /// backend 404s that case, and given the small fixed seed matrix an
  /// unseeded pair is an expected outcome, not an error. Mirrors
  /// `MetarApi.fetch` and `GeocodingApi.search`.
  Future<HistoricalReading?> fetch(String location, String date) async {
    try {
      return await guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/historical',
          queryParameters: {'location': location, 'date': date},
        );
        return HistoricalReading.fromJson(response.data!);
      });
    } on ServerError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
