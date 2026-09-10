import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/network/app_error.dart';

double? _asDoubleOrNull(dynamic value) =>
    value == null ? null : (value as num).toDouble();

/// One day's Open-Meteo Archive reading (ERA5/ERA5-Land reanalysis) for a
/// single location. Every field is independently nullable — Open-Meteo
/// omits some fields for some days/points, and a missing value must never
/// be coerced to 0: under-reporting is the one unacceptable failure here.
class ArchiveReading {
  final String date;
  final double? tempMaxC;
  final double? tempMinC;
  final double? tempMeanC;

  /// A real daily precipitation total (unlike the old ERA5-seed path's
  /// 1-hour accumulation) — see `backend/app/providers/open_meteo_archive.py`.
  final double? precipSumMm;
  final double? windSpeedMaxKmh;
  final double? windDirectionDominantDeg;

  const ArchiveReading({
    required this.date,
    this.tempMaxC,
    this.tempMinC,
    this.tempMeanC,
    this.precipSumMm,
    this.windSpeedMaxKmh,
    this.windDirectionDominantDeg,
  });

  factory ArchiveReading.fromJson(Map<String, dynamic> json) {
    return ArchiveReading(
      date: json['date'] as String,
      tempMaxC: _asDoubleOrNull(json['temp_max_c']),
      tempMinC: _asDoubleOrNull(json['temp_min_c']),
      tempMeanC: _asDoubleOrNull(json['temp_mean_c']),
      precipSumMm: _asDoubleOrNull(json['precip_sum_mm']),
      windSpeedMaxKmh: _asDoubleOrNull(json['wind_speed_max_kmh']),
      windDirectionDominantDeg: _asDoubleOrNull(json['wind_direction_dominant_deg']),
    );
  }
}

/// `GET /historical/archive`'s response: one reading for the requested
/// (location, date), plus — same request — the reading for the same
/// calendar date one year earlier, for the "same day, different year"
/// comparison panel. [previousYearReading] is null when the backend has no
/// data for that earlier date (e.g. it falls outside archive coverage).
class HistoricalArchive {
  final double latitude;
  final double longitude;
  final String? locationName;
  final ArchiveReading reading;
  final ArchiveReading? previousYearReading;

  const HistoricalArchive({
    required this.latitude,
    required this.longitude,
    this.locationName,
    required this.reading,
    this.previousYearReading,
  });

  factory HistoricalArchive.fromJson(Map<String, dynamic> json) {
    return HistoricalArchive(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      locationName: json['location_name'] as String?,
      reading: ArchiveReading.fromJson(json['reading'] as Map<String, dynamic>),
      previousYearReading: json['previous_year_reading'] == null
          ? null
          : ArchiveReading.fromJson(
              json['previous_year_reading'] as Map<String, dynamic>),
    );
  }
}

/// Wraps `GET /historical/archive` — any location on Earth, any date from
/// 1940 to a few days ago, backed by Open-Meteo's Archive API (itself
/// ERA5/ERA5-Land reanalysis).
class HistoricalApi {
  final Dio _dio;

  HistoricalApi(this._dio);

  /// Returns null when the backend has no archive data for this exact
  /// (location, date) — an expected outcome for a date outside coverage,
  /// not an error. Mirrors `GeocodingApi.search`/`MetarApi.fetch`.
  Future<HistoricalArchive?> fetchArchive({
    required double latitude,
    required double longitude,
    required String date,
    String? name,
  }) async {
    try {
      return await guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/historical/archive',
          queryParameters: {
            'lat': latitude,
            'lon': longitude,
            'date': date,
            'name': ?name,
          },
        );
        return HistoricalArchive.fromJson(response.data!);
      });
    } on ServerError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
